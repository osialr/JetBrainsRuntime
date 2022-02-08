package sun.awt;

import sun.font.FontUtilities;
import sun.util.logging.PlatformLogger;

import java.awt.*;
import java.awt.event.InvocationEvent;
import java.lang.ref.WeakReference;
import java.security.AccessController;
import java.security.PrivilegedAction;
import java.util.*;
import java.util.List;
import java.util.concurrent.*;
import java.util.concurrent.atomic.AtomicReference;

/**
 * Used to perform a cross threads (EventDispatch, Toolkit) execution so that the execution does not cause a deadlock.
 */
public class AWTThreading {
    private static final PlatformLogger logger = PlatformLogger.getLogger("sun.awt.AWTThreading");

    private final Thread eventDispatchThread;
    private ExecutorService executor;
    // every invokeAndWait() pushes a queue of invocations
    private final Stack<TrackingQueue> invocations = new Stack<>();

    private int level; // re-entrance level

    private final List<CompletableFuture<Void>> eventDispatchThreadNotifiers = Collections.synchronizedList(new ArrayList<>());

    // invocations should be dispatched on proper EDT (per AppContext)
    private static final Map<Thread, AWTThreading> EDT_TO_INSTANCE_MAP = new ConcurrentHashMap<>();

    private static class TrackingQueue extends LinkedBlockingQueue<InvocationEvent> {}

    private AWTThreading(Thread edt) {
        eventDispatchThread = edt;
    }

    /**
     * Executes a callable from EventDispatch thread (EDT). It's assumed the callable either performs a blocking execution on Toolkit
     * or waits a notification from Toolkit. The method is re-entrant.
     * <p>
     * Currently only macOS is supported. The callable can wrap a native obj-c selector. The selector should be executed via
     * [JNFRunLoop performOnMainThreadWaiting:YES ...] so that doAWTRunLoop on AppKit (which is run in [JNFRunLoop javaRunLoopMode]) accepts it.
     * The callable should not call any Java code that would normally be called on EDT.
     * <p>
     * A deadlock can happen when the callable triggers any blocking invocation from Toolkit to EDT, or when Toolkit already waits in
     * such blocking invocation. To avoid that:
     * <ul>
     * <li>The callback execution is delegated to a dedicated pool thread.
     * <li>All invocation events, initiated by Toolkit via invokeAndWait(), are tracked via a dedicated queue.
     * <li>All the tracked invocation events are dispatched on EDT out of order (EventQueue) during the callback execution.
     * <li>In case of a re-entrant method call, all the tracked invocation events coming after the call are dispatched first.
     * </ul><p>
     * When called on non-EDT, or on non-macOS, the method executes the callable just in place.
     */
    public static <T> T executeWaitToolkit(Callable<T> callable) {
        return executeWaitToolkit(callable, -1, null);
    }

    /**
     * Same as {@link #executeWaitToolkit(Callable)}, but without returning a value. If requested (as indicated by
     * the passed parameter), the invoked native method is supposed to wait for the result of invocation on AppKit
     * thread, and vice versa.
     */
    public static void executeWaitToolkit(Task runnable) {
        boolean wait = EventQueue.isDispatchThread();
        executeWaitToolkit(() -> {
            runnable.run(wait);
            return null;
        });
    }

    /**
     * Same as {@link #executeWaitToolkit(Callable)} except that the method waits no longer than the specified timeout.
     */
    public static <T> T executeWaitToolkit(Callable<T> callable, long timeout, TimeUnit unit) {
        if (callable == null) return null;

        boolean isEDT = EventQueue.isDispatchThread();

        if (FontUtilities.isMacOSX && isEDT) {
            AWTThreading instance = getInstance(Thread.currentThread());
            if (instance != null) {
                return instance.execute(callable, timeout, unit);
            }
        }

        if (!isEDT && logger.isLoggable(PlatformLogger.Level.FINE)) {
            // this can cause deadlock if calling thread is holding a lock which EDT might require (e.g. AWT tree lock)
            logger.fine("AWTThreading.executeWaitToolkit invoked from non-EDT thread", new Throwable());
        }

        // fallback to default
        try {
            return callable.call();
        } catch (Exception e) {
            e.printStackTrace();
        }
        return null;
    }

    private <T> T execute(Callable<T> callable, long timeout, TimeUnit unit) {
        assert EventQueue.isDispatchThread();
        if (executor == null) {
            // init on EDT
            AccessController.doPrivileged((PrivilegedAction<?>)() ->
                    executor = new ThreadPoolExecutor(1, Integer.MAX_VALUE,
                            60L, TimeUnit.SECONDS,
                            new SynchronousQueue<>(),
                            new ThreadFactory() {
                                private final ThreadFactory factory = Executors.privilegedThreadFactory();
                                @Override
                                public Thread newThread(Runnable r) {
                                    Thread t = factory.newThread(r);
                                    t.setDaemon(true);
                                    t.setName(AWTThreading.class.getSimpleName() + " " + t.getName());
                                    return t;
                                }
                            })
            );
        }
        level++;
        try {
            TrackingQueue currentQueue;
            synchronized (invocations) {
                if (level == 1 && invocations.size() == 1) {
                    currentQueue = invocations.peek();
                } else {
                    invocations.push(currentQueue = new TrackingQueue());
                }
            }

            FutureTask<T> task = new FutureTask<>(callable) {
                @Override
                protected void done() {
                    synchronized (invocations) {
                        invocations.remove(currentQueue);
                        // add dummy event to wake up the queue
                        currentQueue.add(new InvocationEvent(new Object(), ()  -> {}));
                    }
                }
            };
            executor.execute(task);

            try {
                while (!task.isDone() || !currentQueue.isEmpty()) {
                    InvocationEvent event;
                    if (timeout >= 0 && unit != null) {
                        event = currentQueue.poll(timeout, unit);
                    } else {
                        event = currentQueue.take();
                    }
                    if (event == null) {
                        task.cancel(false);
                        synchronized (invocations) {
                            invocations.remove(currentQueue);
                        }
                        new RuntimeException("Waiting for the invocation event timed out").printStackTrace();
                        break;
                    }
                    event.dispatch();
                }
                return task.isCancelled() ? null : task.get();

            } catch (InterruptedException | ExecutionException e) {
                e.printStackTrace();
            }
        } finally {
            level--;
        }
        return null;
    }

    /**
     * Used by implementation.
     * Creates an invocation event and adds it to the tracking queue.
     * It's assumed the event is then posted to EventQueue.
     * The following is provided:
     * <ul>
     * <li>If the event is first dispatched from EventQueue - it gets removed from the tracking queue.
     * <li>If the event is first dispatched from the tracking queue - its dispatching on EventQueue will be noop.
     * <ul>
     *
     * @param source the source of the event
     * @param onDispatch called back on event dispatching
     * @param onDispose called back on event disposing
     */
    public static InvocationEvent createAndTrackInvocationEvent(Object source,
                                                                Runnable onDispatch,
                                                                Runnable onDispose,
                                                                boolean catchThrowables)
    {
        AWTThreading instance = getInstance(source);
        if (instance != null) {
            synchronized (instance.invocations) {
                if (instance.invocations.isEmpty()) {
                    instance.invocations.push(new TrackingQueue());
                }
                final TrackingQueue queue = instance.invocations.peek();
                final AtomicReference<InvocationEvent> eventRef = new AtomicReference<>();

                eventRef.set(new InvocationEvent(
                    source,
                    onDispatch,
                    // This completion listener will be called on EDT in either case (dispatch/dispose)
                    // and will remove the invocation event from the tracking queue.
                    new Runnable() {
                        final WeakReference<TrackingQueue> queueRef = new WeakReference<>(queue);

                        @Override
                        public void run() {
                            TrackingQueue queue = queueRef.get();
                            queueRef.clear();
                            if (queue != null) {
                                if (!eventRef.get().isDispatched() && onDispose != null) {
                                    onDispose.run();
                                }
                                queue.remove(eventRef.get());
                            }
                        }
                    },
                    catchThrowables)
                {
                    @Override
                    public void dispatch() {
                        if (!isDispatched()) {
                            super.dispatch();
                        }
                    }
                });

                queue.add(eventRef.get());
                return eventRef.get();
            }
        }
        return new InvocationEvent(source, onDispatch, onDispose, catchThrowables);
    }

    public static AWTThreading getInstance(Object obj) {
        if (obj == null) {
            return getInstance(Toolkit.getDefaultToolkit().getSystemEventQueue());
        }

        AppContext appContext = SunToolkit.targetToAppContext(obj);
        if (appContext == null) {
            return getInstance(Toolkit.getDefaultToolkit().getSystemEventQueue());
        }

        return getInstance((EventQueue)appContext.get(AppContext.EVENT_QUEUE_KEY));
    }

    public static AWTThreading getInstance(EventQueue eq) {
        if (eq == null) return null;

        return getInstance(AWTAccessor.getEventQueueAccessor().getDispatchThread(eq));
    }

    public static AWTThreading getInstance(Thread edt) {
        assert edt != null;

        return EDT_TO_INSTANCE_MAP.computeIfAbsent(edt, key -> new AWTThreading(edt));
    }

    public Thread getEventDispatchThread() {
        return eventDispatchThread;
    }

    public void notifyEventDispatchThreadFree() {
        assert EventQueue.isDispatchThread();

        List<CompletableFuture<Void>> copy;
        // {eventDispatchThreadNotifiers} is the internal mutex for the collection
        synchronized (eventDispatchThreadNotifiers) {
            copy = List.copyOf(eventDispatchThreadNotifiers);
        }
        // notify callbacks out of the {eventDispatchThreadNotifiers} synchronization
        copy.forEach(f -> f.complete(null));
    }

    /**
     * Sets a callback and returns a {@code CompletableFuture} handling the case when the associated EventDispatch thread
     * has gone sleeping and stopped dispatching events because of empty EventQueue. The callback is called on the
     * EventDispatch thread.
     */
    public CompletableFuture<Void> notifyOnEventDispatchThreadFree(Runnable runnable) {
        if (runnable == null) runnable = () -> {};

        CompletableFuture<Void> future = new CompletableFuture<>();
        future.thenRun(runnable);
        future.whenComplete((r, e) -> eventDispatchThreadNotifiers.remove(future));

        eventDispatchThreadNotifiers.add(future);
        return future;
    }

    public interface Task {
        void run(boolean wait);
    }
}
