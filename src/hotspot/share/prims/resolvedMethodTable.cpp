/*
 * Copyright (c) 2017, 2019, Oracle and/or its affiliates. All rights reserved.
 * DO NOT ALTER OR REMOVE COPYRIGHT NOTICES OR THIS FILE HEADER.
 *
 * This code is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 only, as
 * published by the Free Software Foundation.
 *
 * This code is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
 * FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * version 2 for more details (a copy is included in the LICENSE file that
 * accompanied this code).
 *
 * You should have received a copy of the GNU General Public License version
 * 2 along with this work; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * Please contact Oracle, 500 Oracle Parkway, Redwood Shores, CA 94065 USA
 * or visit www.oracle.com if you need additional information or have any
 * questions.
 *
 */

#include "precompiled.hpp"
#include "classfile/javaClasses.hpp"
#include "gc/shared/oopStorage.inline.hpp"
#include "gc/shared/oopStorageSet.hpp"
#include "logging/log.hpp"
#include "memory/allocation.hpp"
#include "memory/resourceArea.hpp"
#include "memory/universe.hpp"
#include "oops/access.inline.hpp"
#include "oops/method.hpp"
#include "oops/oop.inline.hpp"
#include "oops/weakHandle.inline.hpp"
#include "prims/resolvedMethodTable.hpp"
#include "runtime/atomic.hpp"
#include "runtime/handles.inline.hpp"
#include "runtime/interfaceSupport.inline.hpp"
#include "runtime/mutexLocker.hpp"
#include "runtime/safepointVerifiers.hpp"
#include "runtime/timerTrace.hpp"
#include "utilities/concurrentHashTable.inline.hpp"
#include "utilities/concurrentHashTableTasks.inline.hpp"
#include "utilities/macros.hpp"

// 2^24 is max size
static const size_t END_SIZE = 24;
// If a chain gets to 32 something might be wrong
static const size_t GROW_HINT = 32;

static const size_t ResolvedMethodTableSizeLog = 10;

unsigned int method_hash(const Method* method) {
  unsigned int name_hash = method->name()->identity_hash();
  unsigned int signature_hash = method->signature()->identity_hash();
  return name_hash ^ signature_hash;
}

typedef ConcurrentHashTable<ResolvedMethodTableConfig,
                            mtClass> ResolvedMethodTableHash;

class ResolvedMethodTableConfig : public AllStatic {
 private:
 public:
  typedef WeakHandle<vm_resolved_method_table_data> Value;

  static uintx get_hash(Value const& value, bool* is_dead) {
    oop val_oop = value.peek();
    if (val_oop == NULL) {
      *is_dead = true;
      return 0;
    }
    *is_dead = false;
    Method* method = java_lang_invoke_ResolvedMethodName::vmtarget(val_oop);
    return method_hash(method);
  }

  // We use default allocation/deallocation but counted
  static void* allocate_node(size_t size, Value const& value) {
    ResolvedMethodTable::item_added();
    return AllocateHeap(size, mtClass);
  }
  static void free_node(void* memory, Value const& value) {
    value.release();
    FreeHeap(memory);
    ResolvedMethodTable::item_removed();
  }
};

static ResolvedMethodTableHash* _local_table           = NULL;
static size_t                   _current_size          = (size_t)1 << ResolvedMethodTableSizeLog;

volatile bool            ResolvedMethodTable::_has_work              = false;

volatile size_t          _items_count           = 0;
volatile size_t          _uncleaned_items_count = 0;

void ResolvedMethodTable::create_table() {
  _local_table  = new ResolvedMethodTableHash(ResolvedMethodTableSizeLog, END_SIZE, GROW_HINT);
  log_trace(membername, table)("Start size: " SIZE_FORMAT " (" SIZE_FORMAT ")",
                               _current_size, ResolvedMethodTableSizeLog);
}

size_t ResolvedMethodTable::table_size() {
  return (size_t)1 << _local_table->get_size_log2(Thread::current());
}

class ResolvedMethodTableLookup : StackObj {
 private:
  Thread*       _thread;
  uintx         _hash;
  const Method* _method;
  Handle        _found;

 public:
  ResolvedMethodTableLookup(Thread* thread, uintx hash, const Method* key)
    : _thread(thread), _hash(hash), _method(key) {
  }
  uintx get_hash() const {
    return _hash;
  }
  bool equals(WeakHandle<vm_resolved_method_table_data>* value, bool* is_dead) {
    oop val_oop = value->peek();
    if (val_oop == NULL) {
      // dead oop, mark this hash dead for cleaning
      *is_dead = true;
      return false;
    }
    bool equals = _method == java_lang_invoke_ResolvedMethodName::vmtarget(val_oop);
    if (!equals) {
      return false;
    }
    // Need to resolve weak handle and Handleize through possible safepoint.
    _found = Handle(_thread, value->resolve());
    return true;
  }
};


class ResolvedMethodGet : public StackObj {
  Thread*       _thread;
  const Method* _method;
  Handle        _return;
public:
  ResolvedMethodGet(Thread* thread, const Method* method) : _thread(thread), _method(method) {}
  void operator()(WeakHandle<vm_resolved_method_table_data>* val) {
    oop result = val->resolve();
    assert(result != NULL, "Result should be reachable");
    _return = Handle(_thread, result);
    log_get();
  }
  oop get_res_oop() {
    return _return();
  }
  void log_get() {
    LogTarget(Trace, membername, table) log;
    if (log.is_enabled()) {
      ResourceMark rm;
      log.print("ResolvedMethod entry found for %s",
                _method->name_and_sig_as_C_string());
    }
  }
};

oop ResolvedMethodTable::find_method(const Method* method) {
  Thread* thread = Thread::current();

  ResolvedMethodTableLookup lookup(thread, method_hash(method), method);
  ResolvedMethodGet rmg(thread, method);
  _local_table->get(thread, lookup, rmg);

  return rmg.get_res_oop();
}

static void log_insert(const Method* method) {
  LogTarget(Debug, membername, table) log;
  if (log.is_enabled()) {
    ResourceMark rm;
    log.print("ResolvedMethod entry added for %s",
              method->name_and_sig_as_C_string());
  }
}

oop ResolvedMethodTable::add_method(const Method* method, Handle rmethod_name) {
  Thread* thread = Thread::current();

  ResolvedMethodTableLookup lookup(thread, method_hash(method), method);
  ResolvedMethodGet rmg(thread, method);

  while (true) {
    if (_local_table->get(thread, lookup, rmg)) {
      return rmg.get_res_oop();
    }
    WeakHandle<vm_resolved_method_table_data> wh = WeakHandle<vm_resolved_method_table_data>::create(rmethod_name);
    // The hash table takes ownership of the WeakHandle, even if it's not inserted.
    if (_local_table->insert(thread, lookup, wh)) {
      log_insert(method);
      return wh.resolve();
    }
  }
}

void ResolvedMethodTable::item_added() {
  Atomic::inc(&_items_count);
}

void ResolvedMethodTable::item_removed() {
  Atomic::dec(&_items_count);
  log_trace(membername, table) ("ResolvedMethod entry removed");
}

double ResolvedMethodTable::get_load_factor() {
  return (double)_items_count/_current_size;
}

double ResolvedMethodTable::get_dead_factor() {
  return (double)_uncleaned_items_count/_current_size;
}

static const double PREF_AVG_LIST_LEN = 2.0;
// If we have as many dead items as 50% of the number of bucket
static const double CLEAN_DEAD_HIGH_WATER_MARK = 0.5;

void ResolvedMethodTable::check_concurrent_work() {
  if (_has_work) {
    return;
  }

  double load_factor = get_load_factor();
  double dead_factor = get_dead_factor();
  // We should clean/resize if we have more dead than alive,
  // more items than preferred load factor or
  // more dead items than water mark.
  if ((dead_factor > load_factor) ||
      (load_factor > PREF_AVG_LIST_LEN) ||
      (dead_factor > CLEAN_DEAD_HIGH_WATER_MARK)) {
    log_debug(membername, table)("Concurrent work triggered, live factor: %g dead factor: %g",
                                 load_factor, dead_factor);
    trigger_concurrent_work();
  }
}

void ResolvedMethodTable::trigger_concurrent_work() {
  MutexLocker ml(Service_lock, Mutex::_no_safepoint_check_flag);
  _has_work = true;
  Service_lock->notify_all();
}

void ResolvedMethodTable::do_concurrent_work(JavaThread* jt) {
  _has_work = false;
  double load_factor = get_load_factor();
  log_debug(membername, table)("Concurrent work, live factor: %g", load_factor);
  // We prefer growing, since that also removes dead items
  if (load_factor > PREF_AVG_LIST_LEN && !_local_table->is_max_size_reached()) {
    grow(jt);
  } else {
    clean_dead_entries(jt);
  }
}

void ResolvedMethodTable::grow(JavaThread* jt) {
  ResolvedMethodTableHash::GrowTask gt(_local_table);
  if (!gt.prepare(jt)) {
    return;
  }
  log_trace(membername, table)("Started to grow");
  {
    TraceTime timer("Grow", TRACETIME_LOG(Debug, membername, table, perf));
    while (gt.do_task(jt)) {
      gt.pause(jt);
      {
        ThreadBlockInVM tbivm(jt);
      }
      gt.cont(jt);
    }
  }
  gt.done(jt);
  _current_size = table_size();
  log_info(membername, table)("Grown to size:" SIZE_FORMAT, _current_size);
}

struct ResolvedMethodTableDoDelete : StackObj {
  void operator()(WeakHandle<vm_resolved_method_table_data>* val) {
    /* do nothing */
  }
};

struct ResolvedMethodTableDeleteCheck : StackObj {
  long _count;
  long _item;
  ResolvedMethodTableDeleteCheck() : _count(0), _item(0) {}
  bool operator()(WeakHandle<vm_resolved_method_table_data>* val) {
    ++_item;
    oop tmp = val->peek();
    if (tmp == NULL) {
      ++_count;
      return true;
    } else {
      return false;
    }
  }
};

void ResolvedMethodTable::clean_dead_entries(JavaThread* jt) {
  ResolvedMethodTableHash::BulkDeleteTask bdt(_local_table);
  if (!bdt.prepare(jt)) {
    return;
  }
  ResolvedMethodTableDeleteCheck stdc;
  ResolvedMethodTableDoDelete stdd;
  {
    TraceTime timer("Clean", TRACETIME_LOG(Debug, membername, table, perf));
    while(bdt.do_task(jt, stdc, stdd)) {
      bdt.pause(jt);
      {
        ThreadBlockInVM tbivm(jt);
      }
      bdt.cont(jt);
    }
    bdt.done(jt);
  }
  log_info(membername, table)("Cleaned %ld of %ld", stdc._count, stdc._item);
}
void ResolvedMethodTable::reset_dead_counter() {
  _uncleaned_items_count = 0;
}

void ResolvedMethodTable::inc_dead_counter(size_t ndead) {
  size_t total = Atomic::add(&_uncleaned_items_count, ndead);
  log_trace(membername, table)(
     "Uncleaned items:" SIZE_FORMAT " added: " SIZE_FORMAT " total:" SIZE_FORMAT,
     _uncleaned_items_count, ndead, total);
}

// After the parallel walk this method must be called to trigger
// cleaning. Note it might trigger a resize instead.
void ResolvedMethodTable::finish_dead_counter() {
  check_concurrent_work();
}

#if INCLUDE_JVMTI
class AdjustMethodEntries : public StackObj {
  bool* _trace_name_printed;
public:
  AdjustMethodEntries(bool* trace_name_printed) : _trace_name_printed(trace_name_printed) {};
  bool operator()(WeakHandle<vm_resolved_method_table_data>* entry) {
    oop mem_name = entry->peek();
    if (mem_name == NULL) {
      // Removed
      return true;
    }

    Method* old_method = (Method*)java_lang_invoke_ResolvedMethodName::vmtarget(mem_name);

    if (old_method->is_old()) {

      Method* new_method = (old_method->is_deleted()) ?
                            Universe::throw_no_such_method_error() :
                            old_method->get_new_method();
      java_lang_invoke_ResolvedMethodName::set_vmtarget(mem_name, new_method);

      ResourceMark rm;
      if (!(*_trace_name_printed)) {
        log_info(redefine, class, update)("adjust: name=%s", old_method->method_holder()->external_name());
         *_trace_name_printed = true;
      }
      log_debug(redefine, class, update, constantpool)
        ("ResolvedMethod method update: %s(%s)",
         new_method->name()->as_C_string(), new_method->signature()->as_C_string());
    }

    return true;
  }
};

// It is called at safepoint only for RedefineClasses
void ResolvedMethodTable::adjust_method_entries(bool * trace_name_printed) {
  assert(SafepointSynchronize::is_at_safepoint(), "only called at safepoint");
  // For each entry in RMT, change to new method
  AdjustMethodEntries adjust(trace_name_printed);
  _local_table->do_safepoint_scan(adjust);
}
#endif // INCLUDE_JVMTI

// (DCEVM) It is called at safepoint only for RedefineClasses
void ResolvedMethodTable::adjust_method_entries_dcevm(bool * trace_name_printed) {
  assert(SafepointSynchronize::is_at_safepoint(), "only called at safepoint");
  // For each entry in RMT, change to new method
  GrowableArray<oop>* oops_to_add = new GrowableArray<oop>();

  for (int i = 0; i < _the_table->table_size(); ++i) {
    for (ResolvedMethodEntry* entry = _the_table->bucket(i);
         entry != NULL;
         entry = entry->next()) {

      oop mem_name = entry->object_no_keepalive();
      // except ones removed
      if (mem_name == NULL) {
        continue;
      }
      Method* old_method = (Method*)java_lang_invoke_ResolvedMethodName::vmtarget(mem_name);

      if (old_method->is_old()) {

        // Method* new_method;
        if (old_method->is_deleted()) {
          // FIXME:(DCEVM) - check if exception can be thrown
          // new_method = Universe::throw_no_such_method_error();
          continue;
        }

        InstanceKlass* newer_klass = InstanceKlass::cast(old_method->method_holder()->new_version());
        Method* newer_method = newer_klass->method_with_idnum(old_method->orig_method_idnum());

        log_info(redefine, class, load, exceptions)("Adjusting method: '%s' of new class %s", newer_method->name_and_sig_as_C_string(), newer_klass->name()->as_C_string());

        assert(newer_klass == newer_method->method_holder(), "call after swapping redefined guts");
        assert(newer_method != NULL, "method_with_idnum() should not be NULL");
        assert(old_method != newer_method, "sanity check");

        if (_the_table->lookup(newer_method) != NULL) {
          // old method was already adjusted if new method exists in _the_table
            continue;
        }

        java_lang_invoke_ResolvedMethodName::set_vmtarget(mem_name, newer_method);
        java_lang_invoke_ResolvedMethodName::set_vmholder_offset(mem_name, newer_method);

        newer_klass->set_has_resolved_methods();
        oops_to_add->append(mem_name);

        ResourceMark rm;
        if (!(*trace_name_printed)) {
          log_info(redefine, class, update)("adjust: name=%s", old_method->method_holder()->external_name());
           *trace_name_printed = true;
        }
        log_debug(redefine, class, update, constantpool)
          ("ResolvedMethod method update: %s(%s)",
           newer_method->name()->as_C_string(), newer_method->signature()->as_C_string());
      }
    }
    for (int i = 0; i < oops_to_add->length(); i++) {
        oop mem_name = oops_to_add->at(i);
        Method* method = (Method*)java_lang_invoke_ResolvedMethodName::vmtarget(mem_name);
        _the_table->basic_add(method, Handle(Thread::current(), mem_name));
    }
  }
}

// Verification
class VerifyResolvedMethod : StackObj {
 public:
  bool operator()(WeakHandle<vm_resolved_method_table_data>* val) {
    oop obj = val->peek();
    if (obj != NULL) {
      Method* method = (Method*)java_lang_invoke_ResolvedMethodName::vmtarget(obj);
      guarantee(method->is_method(), "Must be");
      guarantee(!method->is_old(), "Must be");
    }
    return true;
  };
};

size_t ResolvedMethodTable::items_count() {
  return _items_count;
}

void ResolvedMethodTable::verify() {
  VerifyResolvedMethod vcs;
  if (!_local_table->try_scan(Thread::current(), vcs)) {
    log_info(membername, table)("verify unavailable at this moment");
  }
}
