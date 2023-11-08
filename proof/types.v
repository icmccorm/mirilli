From Coq Require Import List.

(* define a constant 'PointerSize' *)
Definition PointerSize := 8.

Inductive SharedType: Type :=
| Int (b : nat)
| Float (b : nat)
| Unit.

Definition size_of_shared (t: SharedType) : nat :=
    match t with
    | Int b => b
    | Float b => b
    | Unit => 0
    end.

Inductive LLVMType : Type :=
| LLVMSized (t: LLVMSizedType)
| LLVMFunction (t1 t2 : LLVMType)
with LLVMSizedType : Type :=
| LLVMProduct (l: list LLVMSizedType)
| LLVMShared (t: SharedType)
| OpaquePtr.



Fixpoint size_of_llvm_type (t: LLVMType) : nat :=
    match t with
    | OpaquePtr => PointerSize
    | LLVMProduct l => fold_left (fun acc x => acc + size_of_llvm_type x) l 0
    | LLVMShared t => size_of_shared t
    | LLVMFunction t1 t2 => 8
    end.

Inductive RustType : Type :=
| RustFunction (t1 t2: RustType)
| Scalar (t: RustScalar) 
| RustProduct (l: list RustElement)
with RustScalar : Type := 
| RustShared (t: SharedType)
| Pointer
with RustElement : Type := 
| Element (t: RustType) (b: nat).

Definition size_of_rust_scalar_type (t: RustScalar) :=
    match t with
    | RustShared t => size_of_shared t
    | Pointer => PointerSize
    end.
