# MiriLLI - Usage
Aside from FFI support, MiriLLI is nearly-identical to an unmodified version of Miri. If you have never used Miri before, please review its original README file before using MiriLLI. This can be found within our fork of the Rust compiler in the directory [`src/tools/miri`](./rust/src/tools/miri). Alternatively, you can consult [the latest version](https://github.com/rust-lang/miri) of the README upstream.

MiriLLI needs access to the LLVM bitcode of foreign libraries to be able to call foreign functions. Clang will produce LLVM bitcode files during compilation if you pass it the flag `--save-temps=obj`. In our Docker image, we override the global C and C++ compilers to use these flags by default. This ensures that bitcode files will be produced and stored in the target directory when building a crate that statically links against C or C++ code. Alternatively, you can compile a foreign library separately, assemble its files into a single module with `llvm-as`, and place it in the directory where you invoke Miri. MiriLLI recursively searches for all bitcode files in the directory where it is invoked, so running it is the same as running an unmodified version of Miri (e.g. `cargo miri test`).

We implemented several configuration flags that change the behavior of MiriLLI. Each of these can be set through the `MIRIFLAGS` environment variable. By default, LLVM is allowed to read uninitialized and unaligned memory.

* `-Zmiri-extern-bc-file=[filename.bc]` -  searches for the indicated LLVM bitcode file and uses it as the single source of foreign function definitions. Any other bitcode files present in the root directory will be ignored.

* `-Zmiri-llvm-memory-zeroed` - zero-initializes all static, stack, and heap memory in LLVM.

* `-Zmiri-llvm-enable-alignment-check-all` - checks all memory accesses in LLVM for alignment.

* `-Zmiri-llvm-enable-alignment-check-rust` - checks only memory accesses to Rust-allocated memory for alignment in LLVM.

* `-Zmiri-llvm-log` - Logs several evaluation-specific flags to the file `llvm_flags.csv`. 

## Implementation
As a prerequisite, please review Section III of our paper, which provides a high-level overview MiriLLI's architecture.
Our implementation involves two areas of the Rust toolchain:

1. [Miri](https://github.com/rust-lang/miri) - Located in `src/tools/miri`
2. [LLI](https://llvm.org/docs/CommandGuide/lli.html) - Located in `llvm-project/llvm/lib/ExecutionEngine/`

We used forks of these crates to implement the interface between Miri and LLI:

*  [Inkwell](https://github.com/TheDan64/inkwell) - Fork in [src/inkwell](./rust/src/inkwell)
*  [llvm-sys](https://github.com/tari/llvm-sys.rs) - Fork in [src/llvm-sys](./rust/src/llvm-sys)

Most of the code for our extension to Miri is located in the directory [`src/shims/llvm`](https://github.com/BorrowSanitizer/rust/blob/f225333ae33cc5b750d92e34dafc1bda504cf8a3/src/tools/miri/src/shims/llvm/), which has the following contents:
```
├── convert     // Functions for converting between the value representations used by Rust and LLVM.
├── values      // Value representations for Rust, and LLVM.
├── threads     // The state of a cross-language thread
├── hooks       // Functions that are used to replace LLI's core operations for accessing memory, handling threads, etc.
├── lli.rs      // The `LLI` object, which is the primary interface to LLI from Miri
├── logging.rs  // Additional facilities for logging errors from LLI
├── helpers.rs  // Helper functions used throughout this module and in containing modules
└── mod.rs
```
We refer to this directory as the "LLVM shims module".

This section describes how our modifications affected each of these tools. It contains three parts:

1. **Initialization** - Describes how Miri and LLI are initialized and communicate across foreign function boundaries through function pointers.

2. **Conversion** - Describes how values are converted between the representations used by each interpreter.

3. **Interpretation** - Describes how the control of execution is transferred between Miri and LLI.

Note that all links in this section are relative to a locally downloaded copy of the source code to ensure that they continue working within the archival copy of this repository. This guide does **not** cover every part of our extension in-depth, and it does not try to do so. Our goal is to provide enough detail so that future researchers can know where to start for implementing bug-fixes and extensions.

### Implementation - Initialization
Before executing a crate in Miri, we assemble the bitcode files of its foreign dependencies into a single LLVM module. The path to this module is passed to Miri through the command `-Zmiri-extern-bc-file=[path]`. However, if no path is provided, then Miri will look for any LLVM bitcode files in the root directory where it is being executed, recursively following any filepaths. These changes are implemented within Miri in the file [src/bin/miri.rs](./rust/src/tools/miri/src/bin/miri.rs).

Before setting up Miri's evaluation context, we take the list of paths to bitcode files and assemble them into a single bitcode module. This requires calling the function `LLI::create`, which is exposed by the LLVM shims module in [lli.rs](./rust/src/tools/miri/src/shims/llvm/lli.rs).  This function uses the global LLVM [`Context`](./rust/src/inkwell/src/context.rs) object exposed by Inkwell to create a new LLVM [`Module`](./rust/src/inkwell/src/module.rs) object, using both `Context::create_module` and  `Module::parse_bitcode_from_path`. A new `Module` object is created for each path, and then all modules are merged iteratively using `Module::link_in_module`. We use this combined `Module` and the global `Context` to create a new instance of the struct `LLI`.
```
#[self_referencing]
pub struct LLI {
    pub context: Context,
    #[borrows(context)]
    #[not_covariant]
    pub module: Module<'this>,
    #[borrows(context)]
    #[not_covariant]
    pub engine: Option<ExecutionEngine<'this>>,
}
```
We implemented LLI using [Ouroboros](https://github.com/someguynamedjosh/ouroboros), a library that provides a mechanism for creating self-referential structs. This is the only way to encapsulate both a `Context` and a `Module` object within the same struct, since `Module` has a lifetime dependent on the `Context` object. Since `Context` is a singular, global object, we also store this instance of `LLI` within a static, interior mutable variable.
```
pub static LLVM_INTERPRETER: ReentrantMutex<RefCell<Option<LLI>>> =
    ReentrantMutex::new(RefCell::new(None));
```
We acquire this mutex to access the `LLI` object whenever we need to interact with a foreign library. For example, before initializing Miri in [src/eval.rs](./rust/src/tools/miri/src/eval.rs), we call `LLI::run_constructors` to call all global constructors for the LLVM module. In the same file, we call `LLI::run_destructors` before terminating Miri. We need this to be a `ReentrantMutex` for the case when a Rust function calls a foreign function, which calls a Rust function, which calls a foreign function. In this case, the lock for `LLI` is acquired to handle the first call, but then we need to access it again up the callstack. Since Miri is single-threaded, we can soundly re-enter the mutex here. 

We wait to initialize the [`ExecutionEngine`](./rust/src/inkwell/src/execution_engine.rs) component of `LLI` when Miri encounters a foreign function. At that point, we call `LLI::initialize_engine` (this only happens the first time a foreign function is encountered). In addition to creating a new instance of `ExecutionEngine` within the `LLI` object, this function also provides LLI with hooks (function pointers) to a variety of operations:
```
engine.set_miri_free(Some(hooks::llvm_free));
engine.set_miri_malloc(Some(hooks::llvm_malloc));
engine.set_miri_load(Some(hooks::miri_memory_load));
engine.set_miri_store(Some(hooks::miri_memory_store));
engine.set_miri_call_by_name(Some(hooks::miri_call_by_name));
engine.set_miri_call_by_pointer(Some(hooks::miri_call_by_pointer));
engine.set_miri_stack_trace_recorder(Some(hooks::miri_error_trace_recorder));
...
engine.set_miri_interpcx_wrapper(miri as *mut _ as *mut MiriInterpCxOpaque);
```

These hooks replace each of LLI's options for accessing memory, allocating memory, calling functions, recording stack traces of errors, etc. Each hook is defined within the module [hooks](./rust/src/tools/miri/src/shims/llvm/hooks) within the LLVM shims submodule in Miri.

We also store a copy of a mutable borrow against Miri's interpretation context with the function `set_miri_interpcx_wrapper`. Note that this is likely undefined behavior under Tree Borrows, but not a form that is currently exploited. There are two options for fixing this. The first option would require threading a mutable reference to `MiriInterpCx` throughout every foreign function call into LLI. The second option would require making `MiriMachine` interior mutable. Both would require significant changes to the design, and since our goal was not to create a production-ready tool, we avoided fixing this after discovering our error during development. This issue is a great example of why we need better tools for finding errors in multi-language Rust codebases beyond MiriLLI, since MiriLLI is not capable of "bootstrapping" itself to find this bug.

For additional context, we will describe how the hook `hooks::llvm_free` is initialized and accessed across our toolchain. This hook is defined in the file [hooks/memory.rs](./rust/src/tools/miri/src/shims/llvm/hooks/memory.rs). Hooks are typically defined as pairs of functions, with one function converting raw pointers from LLI into Rust's reference types, and the other function handling the actual implementation. For `llvm_free`, we use the following two functions:
```
fn llvm_free_result<'tcx>(ctx: &mut MiriInterpCx<'tcx>, ptr: MiriPointer) -> InterpResult<'tcx>

pub extern "C-unwind" fn llvm_free(ctx_raw: *mut MiriInterpCxOpaque, ptr: MiriPointer) 
```
We pass a pointer to the second function (`llvm_free`) into `inkwell::ExecutionEngine::set_miri_free`. This function was added to Inkwell's original implementation of `ExecutionEngine`, and it calls a foreign function exposed through the LLVM C interface for LLI. 
```
pub fn set_miri_free(&self, free_hook: MiriFreeHook) {
    unsafe { LLVMExecutionEngineSetMiriFree(self.execution_engine_inner(), free_hook) }
}
```
This function and others like it were added to `llvm-sys` in the file [src/execution_engine.rs](./rust/src/llvm-sys/src/execution_engine.rs). 
```
pub fn LLVMExecutionEngineSetMiriFree(
    EE: LLVMExecutionEngineRef,
    IncomingFreeHook: MiriFreeHook,
);
```
This function, along with other extensions, is defined in the header file [llvm/include/llvm-c/ExecutionEngine.h](./rust/src/llvm-project/llvm/include/llvm-c/ExecutionEngine.h)
```
void LLVMExecutionEngineSetMiriFree(LLVMExecutionEngineRef EE,
                                    MiriFreeHook IncomingFreeHook);
```
The function is implemented in the file [llvm/lib/ExecutionEngine/ExecutionEngineBindings.cpp](./rust/src/llvm-project/llvm/lib/ExecutionEngine/ExecutionEngineBindings.cpp)
```
void LLVMExecutionEngineSetMiriFree(LLVMExecutionEngineRef EE,
                                    MiriFreeHook IncomingFree) {
  assert(IncomingFree && "IncomingFree must be non-null");
  auto *ExecEngine = unwrap(EE);
  ExecEngine->setMiriFree(IncomingFree);
}
```
This wraps the innermost implementation of the function, which is defined within [llvm/lib/ExecutionEngine/ExecutionEngine.h](./rust/src/llvm-project/llvm/include/llvm/ExecutionEngine/ExecutionEngine.h).

```
void setMiriFree(MiriFreeHook IncomingFree) { MiriFree = IncomingFree; }
```
The variable `MiriFree` is a field of the class `ExecutionEngine`, which is implemented by [`Interpreter`](./rust/src/llvm-project/llvm/lib/ExecutionEngine/Interpreter/Interpreter.h) to provide the functionality for LLI. The class `ExecutionEngine` is also implemented by LLVM's JIT compilation backend. Inkwell supports both of these backends; we ensure that the interpreter is used by calling `inkwell::Module::create_interpreter_execution_engine` from Rust.

The type `MiriFreeHook` is defined in [llvm/include/llvm-c/Miri.h](rust/src/llvm-project/llvm/include/llvm-c/Miri.h), along with every other type that is used to support interfacing with Miri from LLI. This hook is used whenever we need to free Rust-allocated memory in LLI. Usually, this happens when we pop a stack frame. LLVM stack memory is managed by an instance of the class `MiriAllocaHolder`, which is implemented along with the class `Interpreter` in [llvm/lib/ExecutionEngine/Interpreter/Interpreter.h](./rust/src/llvm-project/llvm/lib/ExecutionEngine/Interpreter/Interpreter.h). Instances of `MiriAllocaHolder` are initialized with a copy of the function pointer to Miri's `llvm_free` implementation. Whenever a new stack memory location is allocated (which is handled by another Miri hook), this struct records a pointer to new allocation. When a stack frame is popped, the destructor for this class runs, freeing the stack memory by calling this hook.
```
class MiriAllocaHolder {
  std::vector<MiriPointer> MiriAllocations;
  MiriFreeHook MiriFree;
  ...
public:
  ~MiriAllocaHolder() {
    for (MiriPointer Tracked : MiriAllocations)
      MiriFree(MiriWrapper, Tracked);
  }
  ...
  void add(MiriPointer Tracked) { MiriAllocations.push_back(Tracked); }
};
```
All hooks and calls between Miri and LLI are implemented through changes to these files, following this pattern.

### Implementation - Conversion
Miri and LLI use different value representations. LLI's value representation is `GenericValue`, which is defined in [llvm/include/llvm/ExecutionEngine/GenericValue.h](./rust/src/llvm-project/llvm/include/llvm/ExecutionEngine/GenericValue.h)

```
struct GenericValue {
  llvm::Type *ValueTy = nullptr;
  struct IntPair {
    unsigned int first;
    unsigned int second;
  };
  union {
    double DoubleVal;
    float FloatVal;
    PointerTy PointerVal;
    struct IntPair UIntPairVal;
    unsigned char Untyped[8];
  };
  APInt IntVal; // also used for long doubles.
  MiriProvenance Provenance = {0, 0};
  std::vector<GenericValue> AggregateVal;
  ...
};
```
Of particular note is the field `Provenance`, of type `MiriProvenance`. This struct is defined in [llvm/include/llvm-c/Miri.h](rust/src/llvm-project/llvm/include/llvm-c/Miri.h)
```
typedef struct MiriProvenance {
  uint64_t alloc_id;
  uint64_t tag;
} MiriProvenance;

typedef struct MiriPointer {
  uint64_t addr;
  MiriProvenance prov;
} MiriPointer;
```
Miri's concrete *provenance* values contain an allocation ID and borrow tag, which are represented here in the `MiriProvenance` struct. We can convert a `GenericValue` into a `MiriPointer` by assembling its provenance value and the `PointerVal` field within its union.
```
inline MiriPointer GVTOMiriPointer(GenericValue &GV) {
  return MiriPointer{
      (uint64_t)(uintptr_t)GV.PointerVal,
      GV.Provenance,
  };
}
```
All Miri-specific LLVM types are defined within [llvm/include/llvm-c/Miri.h](rust/src/llvm-project/llvm/include/llvm-c/Miri.h) and encapsulated by either `llvm-sys` in [llvm-sys/src/miri.rs](rust/src/llvm-sys/src/miri.rs) or Inkwell in [inkwell/src/miri.rs](./rust/src/inkwell/src/miri.rs). The `GenericValue` struct is encapsulated by Inkwell as a struct with the same name. We extended its API to support accessing values as `llvm-sys::MiriPointer` objects. Inkwell's `GenericValue` struct is a thin wrapper around `GenericValueRef`, which has the same functionality. In this case, `GenericValue` is an *owned* instance of `GenericValue`, which is deallocated from the Rust side of the boundary when it is dropped. The struct `GenericValueRef` is owned by the C++ side of the FFI, but it is temporarily borrowed by Rust. The original Inkwell API only provided `GenericValue`. 

We provide APIs for converting instances of `inkwell::GenericValue` or `inkwell::GenericValueRef` into most of Rust's integer or floating point types, or an instance of `llvm-sys::MiriPointer` instance. However, only a subset of these conversions will be valid based on the type of the underlying value. This type can accessed as an instance of `llvm_sys::BasicTypeEnum`. This reflects the dynamic type that the value was last used at, according to the most recent instruction being executed.

Miri uses several value representations, but the one that we are most concerned with is [`OpTy`](./rust/compiler/rustc_const_eval/src/interpret/operand.rs), which is a typed `Operand` to a function. This is provided within the source of Rust's [constant evaluator](./rust/compiler/rustc_const_eval), which Miri extends. Miri's provenance values are an enumeration with two variants.
```
#[derive(Clone, Copy)]
pub enum Provenance {
    Concrete {
        alloc_id: AllocId,
        tag: BorTag,
    },
    Wildcard,
}
```
Pointers with a `Wildcard` provenance value receive an allocation ID and borrow tag of 0 when represented in LLVM as `MiriProvenance`. 

When MiriLLI crosses a foreign function boundary, we need to convert between `OpTy` and `GenericValue`/`GenericValueRef`. The semantics of these conversions are formally defined within our Appendix, and they are implemented in the LLVM shims module. The file [shims/llvm/convert/to_generic_value.rs](./mirilli-artifact/rust/src/tools/miri/src/shims/llvm/convert/to_generic_value.rs)
implements the conversion from `GenericValueRef` to `OpTy`, while [shims/llvm/convert/to_opty.rs](./mirilli-artifact/rust/src/tools/miri/src/shims/llvm/convert/to_generic_value.rs) implements the reverse. We defined our conversion functions based on the ABI differences that we observed during our evaluation. However, we do not claim that this is a complete reimplementation of the X86 ABI. If you find an error when using MiriLLI suggesting that a foreign function binding is incorrect when it is actually correct, then it may be due to a limitation of our conversion layer.

### Implementation - Interpretation
Miri supports multi-threaded programs, but it does not have true multi-threading. Instead, it non-deterministically steps through simulated "threads" of execution. LLI did not have any form of multi-threading, so we needed to modify it to support Miri's version. We also needed a way to coordinate execution between each interpreter. When Miri calls a function, we need it to "suspend" the current thread while LLI takes over, continuing only when the foreign function returns. 

Miri handles foreign function calls in the file [shims/foreign_items.rs](./rust/src/tools/miri/src/shims/foreign_items.rs). The function `emulate_foreign_item_inner` is eventually called when Miri encounters a function that is not defined in any available MIR. If its name matches one of the available "shim" implementations for that target, then the shim is executed. However, as a fallback, if no shims are found, then Miri calls out to LLI to determine if the function is defined in LLVM bitcode. 

From here, if a function is found, then control eventually ends up in `LLI:call_external_llvm_and_store_return`, which prepares for the function call. This function has multiple tasks. It needs to convert each of the `OpTy` arguments into `GenericValue` instances, and also handle certain calling conventions, like variable arguments and struct return pointers. However, once all arguments have been converted, Miri creates a new LLI thread to execute the function using `MiriInterpCx::start_rust_to_lli_thread`. This function is defined in Miri's concurrency module: [src/concurrency/thread.rs](./rust/src/tools/miri/src/concurrency/thread.rs). This function performs two key steps. First, it must communicate across the FFI to LLI and instruct it to create a new internal thread state for the function being called. Then, it needs to set up a "link" between the current Rust thread and the pending LLVM thread. This "link" is an instance of the struct `ThreadLink`, which is defined in [shims/llvm/thread/link.rs](./rust/src/tools/miri/src/shims/llvm/threads/link.rs).
```
pub struct ThreadLink<'tcx> {
    linked_id: ThreadId,
    id: ThreadId,
    link: ThreadLinkDestination<'tcx>,
    source: ThreadLinkSource<'tcx>,
    lli_allocations: Vec<MPlaceTy<'tcx>>,
}
```
It contains an ID for the calling thread (`id`) and an ID for the thread of the function being called (`linked_id`). It also contains a "source" object (`ThreadLinkSource`) and a destination (`ThreadLinkDestination`). The source is the location where a pending return value will be waiting one one side of the foreign function boundary--it's initialized later on, when the return value has been produced. The destination is the location where the return value needs to be copied once the function returns, crossing the foreign boundary. The destination is initialized when the link is created. The `ThreadLink` instance is stored as part of the thread for the function being called, so that when the call ends, the link can be "collapsed," copying the return value back and transferring control to the caller. After creating the new thread for the function call, the old thread is set to join on the new one. The overall process here is identical for when Miri calls an LLVM function, or when LLI calls a function defined in Rust. The implementation of `ThreadLinkSource` and `ThreadLinkDestination` change for each case, and `ThreadLink` handles every valid combination of source and destination, using the same conversion functions to process the return values as we use when passing parameters.

There's a disconnect here, though—we've created a new thread in Miri for a function in LLVM, but Miri does not have direct access to the function or its data. This thread is sort of a "mirror" object; it exists only to reflect that there is an active LLVM thread. When Miri decides to take a step along a thread (implemented in [src/concurrency/thread.rs](./rust/src/tools/miri/src/concurrency/thread.rs)), we check first to see if the thread is mirroring an LLVM thread, and then we call a foreign function to take an actual, concrete step in LLI. 
```
  SchedulingAction::ExecuteStep => {
          let id = this.active_thread();
          if this.in_llvm()? {
              let ready_to_terminate = this.step_lli_thread(id)?;
              ...
          }
    ...
  }
```
The function `step_lli_thread` eventually calls `inkwell::ExecutionEngine::step_thread`, which calls `llvm-sys::LLVMExecutionEngineStepThread`, which calls the matching foreign function in the LLVM C bindings. This eventually ends up in the body of `Interpreter::stepThread`, which is defined in [llvm/lib/ExecutionEngine/Interpreter/Interpreter.cpp](./rust/src/llvm-project/llvm/lib/ExecutionEngine/Interpreter/Interpreter.cpp). Note that the action taken by this function is to switch the current "thread" to a new one, matching the corresponding ID.
```
Interpreter::switchThread(ThreadID);
```
Originally, LLI only supported single-threaded execution. The `Interpreter` had a single stack of `ExecutionContext` objects, with each context representing a stack frame. We extended this design pattern so that the `Interpreter` contains a mapping between thread IDs (word-size integers) and `ExecutionThread` objects, where each `ExecutionThread` contains the stack and other state objects originally contained within the `Interpreter` instance. The `Interpreter` switches between `ExecutionThread` contexts to handle every active LLVM thread. All of these objects are defined within [llvm/lib/ExecutionEngine/Interpreter/Interpreter.h](./rust/src/llvm-project/llvm/lib/ExecutionEngine/Interpreter/Interpreter.h).

Functions for handling the reverse---when LLI calls a Rust function---are defined within [shims/llvm/hooks/calls.rs](./rust/src/tools/miri/src/shims/llvm/hooks/calls.rs). Like the `llvm_free` example shown earlier in section "Implementation - Initialization", each of these functions are accessible from LLI through function pointers. There are two possible situations that can occur when we need to transfer control from LLI to Miri. In the first situation, LLI is attempting to call a function by-name, but it does not have a corresponding definition. In that situation, we use `miri_call_by_name`, which redirects to Miri's shim implementations (as well as a few custom ones we added). We do not have type information for the shim declarations, so we attempt to convert LLVM arguments using a default mapping from LLVM types to Rust types, defined in the helper function `get_equivalent_rust_layout_for_value`. This is not guaranteed to be correct, especially for pointer types, but it works for most shims. 

In the second situation, LLI is attempting to call a function pointer. Here, we use `miri_call_by_pointer` to try and find a corresponding instance for a function defined in MIR. If we locate an instance, then we use its parameter types to guide the conversion, just as we would when calling a foreign LLVM function from Rust.