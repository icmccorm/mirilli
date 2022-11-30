#![feature(rustc_private)]
#![feature(control_flow_enum)]

extern crate rustc_arena;
extern crate rustc_ast;
extern crate rustc_ast_pretty;
extern crate rustc_attr;
extern crate rustc_data_structures;
extern crate rustc_errors;
extern crate rustc_hir;
extern crate rustc_hir_pretty;
extern crate rustc_index;
extern crate rustc_infer;
extern crate rustc_lexer;
extern crate rustc_middle;
extern crate rustc_mir_dataflow;
extern crate rustc_parse;
extern crate rustc_span;
extern crate rustc_target;
extern crate rustc_trait_selection;
extern crate rustc_type_ir;

use rustc_data_structures::fx::FxHashSet;
use rustc_errors::fluent;
use rustc_errors::DiagnosticMessage;
use rustc_hir as hir;
use rustc_middle::ty::layout::{LayoutOf, SizeSkeleton};
use rustc_middle::ty::subst::SubstsRef;
use rustc_middle::ty::TyKind;
use rustc_middle::ty::{self, AdtKind, Ty, TyCtxt, TypeSuperVisitable, TypeVisitable};
use rustc_span::symbol::sym;
use rustc_span::Span;
use rustc_span::DUMMY_SP;
use rustc_target::abi::{Abi, WrappingRange};
use rustc_target::spec::abi::Abi as SpecAbi;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::io::Write;
use std::iter;
use std::ops::ControlFlow;

dylint_linting::impl_late_lint! {
    pub FFICKLE_LATE,
    Warn,
    "Detecting FFI usage",
    FfickleLate::default()
}

use rustc_lint::LateContext;
use rustc_lint::LateLintPass;
#[derive(PartialEq, Eq, Default, Serialize, Deserialize, Hash)]
struct ObservedImproperType {
    discriminant: usize,
    str_rep: String,
    location: String,
}

#[derive(PartialEq, Eq, Default, Serialize, Deserialize, Hash)]
struct ForeignTypeError {
    discriminant: usize,
    str_rep: String,
    abi: String,
}

#[derive(Serialize, Deserialize, Eq, PartialEq, Hash)]
enum ForeignItemType {
    RustFn,
    ForeignFn,
    StaticItem,
}

#[derive(Default, Serialize, Deserialize)]
struct FfickleLate {
    error_locations: HashMap<usize, HashSet<String>>,
    error_id_count: usize,
    error_id_map: HashMap<usize, ForeignTypeError>,
    foreign_functions: ErrorCount,
    static_items: ErrorCount,
    rust_functions: ErrorCount,
}

#[derive(Default, Serialize, Deserialize)]
struct ErrorCount {
    total_items: usize,
    item_error_counts: Vec<HashMap<usize, usize>>,
}

trait ErrorIDStore {
    fn record_errors(
        &mut self,
        errors: Vec<ObservedImproperType>,
        abi_string: &str,
        item_type: ForeignItemType,
    ) -> ();
}
impl ErrorIDStore for FfickleLate {
    fn record_errors(
        &mut self,
        errors: Vec<ObservedImproperType>,
        abi_string: &str,
        item_type: ForeignItemType,
    ) -> () {
        let store = match item_type {
            ForeignItemType::RustFn => &mut self.rust_functions,
            ForeignItemType::ForeignFn => &mut self.foreign_functions,
            ForeignItemType::StaticItem => &mut self.static_items,
        };
        (*store).total_items += 1;
        let mut err_counts = HashMap::<usize, usize>::new();

        for err in errors {
            let foreign_err = ForeignTypeError {
                discriminant: err.discriminant,
                str_rep: err.str_rep,
                abi: abi_string.to_string().replace("\"", ""),
            };
            let id_opt = self.error_id_map.iter().find_map(|(key, val)| {
                if val.eq(&foreign_err) {
                    Some(key)
                } else {
                    None
                }
            });
            let id = match id_opt {
                Some(i) => *i,
                None => {
                    self.error_id_map.insert(self.error_id_count, foreign_err);
                    self.error_id_count += 1;
                    self.error_id_count - 1
                }
            };
            self.error_locations.entry(id).or_default().insert(err.location);
            let count = (err_counts).entry(id).or_insert(0);
            *count += 1;
        }
        (*store).item_error_counts.extend(vec![err_counts]);
    }
}

#[derive(Clone, Copy)]
pub(crate) enum CItemKind {
    Declaration,
    Definition,
}

struct ImproperCTypesVisitor<'a, 'tcx> {
    cx: &'a LateContext<'tcx>,
    mode: CItemKind,
    errors: &'a mut Vec<ObservedImproperType>,
}

enum FfiResult<'tcx> {
    FfiSafe,
    FfiPhantom(Ty<'tcx>),
    FfiUnsafe {
        ty: Ty<'tcx>,
        reason: DiagnosticMessage,
        help: Option<DiagnosticMessage>,
    },
}

pub(crate) fn nonnull_optimization_guaranteed<'tcx>(
    tcx: TyCtxt<'tcx>,
    def: ty::AdtDef<'tcx>,
) -> bool {
    tcx.has_attr(def.did(), sym::rustc_nonnull_optimization_guaranteed)
}

/// `repr(transparent)` structs can have a single non-ZST field, this function returns that
/// field.
pub fn transparent_newtype_field<'a, 'tcx>(
    tcx: TyCtxt<'tcx>,
    variant: &'a ty::VariantDef,
) -> Option<&'a ty::FieldDef> {
    let param_env = tcx.param_env(variant.def_id);
    variant.fields.iter().find(|field| {
        let field_ty = tcx.type_of(field.did);
        let is_zst = tcx
            .layout_of(param_env.and(field_ty))
            .map_or(false, |layout| layout.is_zst());
        !is_zst
    })
}

/// Is type known to be non-null?
fn ty_is_known_nonnull<'tcx>(cx: &LateContext<'tcx>, ty: Ty<'tcx>, mode: CItemKind) -> bool {
    let tcx = cx.tcx;
    match ty.kind() {
        ty::FnPtr(_) => true,
        ty::Ref(..) => true,
        ty::Adt(def, _) if def.is_box() && matches!(mode, CItemKind::Definition) => true,
        ty::Adt(def, substs) if def.repr().transparent() && !def.is_union() => {
            let marked_non_null = nonnull_optimization_guaranteed(tcx, *def);

            if marked_non_null {
                return true;
            }

            // `UnsafeCell` has its niche hidden.
            if def.is_unsafe_cell() {
                return false;
            }

            def.variants()
                .iter()
                .filter_map(|variant| transparent_newtype_field(cx.tcx, variant))
                .any(|field| ty_is_known_nonnull(cx, field.ty(tcx, substs), mode))
        }
        _ => false,
    }
}

/// Given a non-null scalar (or transparent) type `ty`, return the nullable version of that type.
/// If the type passed in was not scalar, returns None.
fn get_nullable_type<'tcx>(cx: &LateContext<'tcx>, ty: Ty<'tcx>) -> Option<Ty<'tcx>> {
    let tcx = cx.tcx;
    Some(match *ty.kind() {
        ty::Adt(field_def, field_substs) => {
            let inner_field_ty = {
                let mut first_non_zst_ty = field_def
                    .variants()
                    .iter()
                    .filter_map(|v| transparent_newtype_field(cx.tcx, v));
                debug_assert_eq!(
                    first_non_zst_ty.clone().count(),
                    1,
                    "Wrong number of fields for transparent type"
                );
                first_non_zst_ty
                    .next_back()
                    .expect("No non-zst fields in transparent type.")
                    .ty(tcx, field_substs)
            };
            return get_nullable_type(cx, inner_field_ty);
        }
        ty::Int(ty) => tcx.mk_mach_int(ty),
        ty::Uint(ty) => tcx.mk_mach_uint(ty),
        ty::RawPtr(ty_mut) => tcx.mk_ptr(ty_mut),
        // As these types are always non-null, the nullable equivalent of
        // Option<T> of these types are their raw pointer counterparts.
        ty::Ref(_region, ty, mutbl) => tcx.mk_ptr(ty::TypeAndMut { ty, mutbl }),
        ty::FnPtr(..) => {
            // There is no nullable equivalent for Rust's function pointers -- you
            // must use an Option<fn(..) -> _> to represent it.
            ty
        }

        // We should only ever reach this case if ty_is_known_nonnull is extended
        // to other types.
        ref _unhandled => {
            return None;
        }
    })
}

/// Check if this enum can be safely exported based on the "nullable pointer optimization". If it
/// can, return the type that `ty` can be safely converted to, otherwise return `None`.
/// Currently restricted to function pointers, boxes, references, `core::num::NonZero*`,
/// `core::ptr::NonNull`, and `#[repr(transparent)]` newtypes.
/// FIXME: This duplicates code in codegen.
pub(crate) fn repr_nullable_ptr<'tcx>(
    cx: &LateContext<'tcx>,
    ty: Ty<'tcx>,
    ckind: CItemKind,
) -> Option<Ty<'tcx>> {
    if let ty::Adt(ty_def, substs) = ty.kind() {
        let field_ty = match &ty_def.variants().raw[..] {
            [var_one, var_two] => match (&var_one.fields[..], &var_two.fields[..]) {
                ([], [field]) | ([field], []) => field.ty(cx.tcx, substs),
                _ => return None,
            },
            _ => return None,
        };

        if !ty_is_known_nonnull(cx, field_ty, ckind) {
            return None;
        }

        // At this point, the field's type is known to be nonnull and the parent enum is Option-like.
        // If the computed size for the field and the enum are different, the nonnull optimization isn't
        // being applied (and we've got a problem somewhere).
        let compute_size_skeleton = |t| SizeSkeleton::compute(t, cx.tcx, cx.param_env).unwrap();
        if !compute_size_skeleton(ty).same_size(compute_size_skeleton(field_ty)) {
            panic!("improper_ctypes: Option nonnull optimization not applied?");
        }

        // Return the nullable type this Option-like enum can be safely represented with.
        let field_ty_abi = &cx.layout_of(field_ty).unwrap().abi;
        if let Abi::Scalar(field_ty_scalar) = field_ty_abi {
            match field_ty_scalar.valid_range(cx) {
                WrappingRange { start: 0, end }
                    if end == field_ty_scalar.size(&cx.tcx).unsigned_int_max() - 1 =>
                {
                    return Some(get_nullable_type(cx, field_ty).unwrap());
                }
                WrappingRange { start: 1, .. } => {
                    return Some(get_nullable_type(cx, field_ty).unwrap());
                }
                WrappingRange { start, end } => {
                    unreachable!("Unhandled start and end range: ({}, {})", start, end)
                }
            };
        }
    }
    None
}

impl<'a, 'tcx> ImproperCTypesVisitor<'a, 'tcx> {
    /// Check if the type is array and emit an unsafe type lint.
    fn check_for_array_ty(&mut self, sp: Span, ty: Ty<'tcx>) -> bool {
        
        if let ty::Array(..) = ty.kind() {
            self.emit_ffi_unsafe_type_lint(
                ty,
                sp,
                fluent::lint::improper_ctypes_array_reason,
                Some(fluent::lint::improper_ctypes_array_help),
            );
            true
        } else {
            false
        }
    }

    /// Checks if the given field's type is "ffi-safe".
    fn check_field_type_for_ffi(
        &self,
        cache: &mut FxHashSet<Ty<'tcx>>,
        field: &ty::FieldDef,
        substs: SubstsRef<'tcx>,
    ) -> FfiResult<'tcx> {
        let field_ty = field.ty(self.cx.tcx, substs);
        if field_ty.has_opaque_types() {
            self.check_type_for_ffi(cache, field_ty)
        } else {
            let field_ty = self
                .cx
                .tcx
                .normalize_erasing_regions(self.cx.param_env, field_ty);
            self.check_type_for_ffi(cache, field_ty)
        }
    }

    /// Checks if the given `VariantDef`'s field types are "ffi-safe".
    fn check_variant_for_ffi(
        &self,
        cache: &mut FxHashSet<Ty<'tcx>>,
        ty: Ty<'tcx>,
        def: ty::AdtDef<'tcx>,
        variant: &ty::VariantDef,
        substs: SubstsRef<'tcx>,
    ) -> FfiResult<'tcx> {
        use FfiResult::*;

        if def.repr().transparent() {
            // Can assume that at most one field is not a ZST, so only check
            // that field's type for FFI-safety.
            if let Some(field) = transparent_newtype_field(self.cx.tcx, variant) {
                self.check_field_type_for_ffi(cache, field, substs)
            } else {
                // All fields are ZSTs; this means that the type should behave
                // like (), which is FFI-unsafe
                FfiUnsafe {
                    ty,
                    reason: fluent::lint::improper_ctypes_struct_zst,
                    help: None,
                }
            }
        } else {
            // We can't completely trust repr(C) markings; make sure the fields are
            // actually safe.
            let mut all_phantom = !variant.fields.is_empty();
            for field in &variant.fields {
                match self.check_field_type_for_ffi(cache, &field, substs) {
                    FfiSafe => {
                        all_phantom = false;
                    }
                    FfiPhantom(..) if def.is_enum() => {
                        return FfiUnsafe {
                            ty,
                            reason: fluent::lint::improper_ctypes_enum_phantomdata,
                            help: None,
                        };
                    }
                    FfiPhantom(..) => {}
                    r => return r,
                }
            }

            if all_phantom {
                FfiPhantom(ty)
            } else {
                FfiSafe
            }
        }
    }

    /// Checks if the given type is "ffi-safe" (has a stable, well-defined
    /// representation which can be exported to C code).
    fn check_type_for_ffi(&self, cache: &mut FxHashSet<Ty<'tcx>>, ty: Ty<'tcx>) -> FfiResult<'tcx> {
        use FfiResult::*;

        let tcx = self.cx.tcx;

        // Protect against infinite recursion, for example
        // `struct S(*mut S);`.
        // FIXME: A recursion limit is necessary as well, for irregular
        // recursive types.
        if !cache.insert(ty) {
            return FfiSafe;
        }

        match *ty.kind() {
            ty::Adt(def, substs) => {
                if def.is_box() && matches!(self.mode, CItemKind::Definition) {
                    if ty.boxed_ty().is_sized(tcx.at(DUMMY_SP), self.cx.param_env) {
                        return FfiSafe;
                    } else {
                        return FfiUnsafe {
                            ty,
                            reason: fluent::lint::improper_ctypes_box,
                            help: None,
                        };
                    }
                }
                if def.is_phantom_data() {
                    return FfiPhantom(ty);
                }
                match def.adt_kind() {
                    AdtKind::Struct | AdtKind::Union => {
                        if !def.repr().c() && !def.repr().transparent() {
                            return FfiUnsafe {
                                ty,
                                reason: if def.is_struct() {
                                    fluent::lint::improper_ctypes_struct_layout_reason
                                } else {
                                    fluent::lint::improper_ctypes_union_layout_reason
                                },
                                help: if def.is_struct() {
                                    Some(fluent::lint::improper_ctypes_struct_layout_help)
                                } else {
                                    Some(fluent::lint::improper_ctypes_union_layout_help)
                                },
                            };
                        }

                        let is_non_exhaustive =
                            def.non_enum_variant().is_field_list_non_exhaustive();
                        if is_non_exhaustive && !def.did().is_local() {
                            return FfiUnsafe {
                                ty,
                                reason: if def.is_struct() {
                                    fluent::lint::improper_ctypes_struct_non_exhaustive
                                } else {
                                    fluent::lint::improper_ctypes_union_non_exhaustive
                                },
                                help: None,
                            };
                        }

                        if def.non_enum_variant().fields.is_empty() {
                            return FfiUnsafe {
                                ty,
                                reason: if def.is_struct() {
                                    fluent::lint::improper_ctypes_struct_fieldless_reason
                                } else {
                                    fluent::lint::improper_ctypes_union_fieldless_reason
                                },
                                help: if def.is_struct() {
                                    Some(fluent::lint::improper_ctypes_struct_fieldless_help)
                                } else {
                                    Some(fluent::lint::improper_ctypes_union_fieldless_help)
                                },
                            };
                        }

                        self.check_variant_for_ffi(cache, ty, def, def.non_enum_variant(), substs)
                    }
                    AdtKind::Enum => {
                        if def.variants().is_empty() {
                            // Empty enums are okay... although sort of useless.
                            return FfiSafe;
                        }

                        // Check for a repr() attribute to specify the size of the
                        // discriminant.
                        if !def.repr().c() && !def.repr().transparent() && def.repr().int.is_none()
                        {
                            // Special-case types like `Option<extern fn()>`.
                            if repr_nullable_ptr(self.cx, ty, self.mode).is_none() {
                                return FfiUnsafe {
                                    ty,
                                    reason: fluent::lint::improper_ctypes_enum_repr_reason,
                                    help: Some(fluent::lint::improper_ctypes_enum_repr_help),
                                };
                            }
                        }

                        if def.is_variant_list_non_exhaustive() && !def.did().is_local() {
                            return FfiUnsafe {
                                ty,
                                reason: fluent::lint::improper_ctypes_non_exhaustive,
                                help: None,
                            };
                        }

                        // Check the contained variants.
                        for variant in def.variants() {
                            let is_non_exhaustive = variant.is_field_list_non_exhaustive();
                            if is_non_exhaustive && !variant.def_id.is_local() {
                                return FfiUnsafe {
                                    ty,
                                    reason: fluent::lint::improper_ctypes_non_exhaustive_variant,
                                    help: None,
                                };
                            }

                            match self.check_variant_for_ffi(cache, ty, def, variant, substs) {
                                FfiSafe => (),
                                r => return r,
                            }
                        }

                        FfiSafe
                    }
                }
            }

            ty::Char => FfiUnsafe {
                ty,
                reason: fluent::lint::improper_ctypes_char_reason,
                help: Some(fluent::lint::improper_ctypes_char_help),
            },

            ty::Int(ty::IntTy::I128) | ty::Uint(ty::UintTy::U128) => FfiUnsafe {
                ty,
                reason: fluent::lint::improper_ctypes_128bit,
                help: None,
            },

            // Primitive types with a stable representation.
            ty::Bool | ty::Int(..) | ty::Uint(..) | ty::Float(..) | ty::Never => FfiSafe,

            ty::Slice(_) => FfiUnsafe {
                ty,
                reason: fluent::lint::improper_ctypes_slice_reason,
                help: Some(fluent::lint::improper_ctypes_slice_help),
            },

            ty::Dynamic(..) => FfiUnsafe {
                ty,
                reason: fluent::lint::improper_ctypes_dyn,
                help: None,
            },

            ty::Str => FfiUnsafe {
                ty,
                reason: fluent::lint::improper_ctypes_str_reason,
                help: Some(fluent::lint::improper_ctypes_str_help),
            },

            ty::Tuple(..) => FfiUnsafe {
                ty,
                reason: fluent::lint::improper_ctypes_tuple_reason,
                help: Some(fluent::lint::improper_ctypes_tuple_help),
            },

            ty::RawPtr(ty::TypeAndMut { ty, .. }) | ty::Ref(_, ty, _)
                if {
                    matches!(self.mode, CItemKind::Definition)
                        && ty.is_sized(self.cx.tcx.at(DUMMY_SP), self.cx.param_env)
                } =>
            {
                FfiSafe
            }

            ty::RawPtr(ty::TypeAndMut { ty, .. })
                if match ty.kind() {
                    ty::Tuple(tuple) => tuple.is_empty(),
                    _ => false,
                } =>
            {
                FfiSafe
            }

            ty::RawPtr(ty::TypeAndMut { ty, .. }) | ty::Ref(_, ty, _) => {
                self.check_type_for_ffi(cache, ty)
            }

            ty::Array(inner_ty, _) => self.check_type_for_ffi(cache, inner_ty),

            ty::FnPtr(sig) => {
                if self.is_internal_abi(sig.abi()) {
                    return FfiUnsafe {
                        ty,
                        reason: fluent::lint::improper_ctypes_fnptr_reason,
                        help: Some(fluent::lint::improper_ctypes_fnptr_help),
                    };
                }

                let sig = tcx.erase_late_bound_regions(sig);
                if !sig.output().is_unit() {
                    let r = self.check_type_for_ffi(cache, sig.output());
                    match r {
                        FfiSafe => {}
                        _ => {
                            return r;
                        }
                    }
                }
                for arg in sig.inputs() {
                    let r = self.check_type_for_ffi(cache, *arg);
                    match r {
                        FfiSafe => {}
                        _ => {
                            return r;
                        }
                    }
                }
                FfiSafe
            }

            ty::Foreign(..) => FfiSafe,

            // While opaque types are checked for earlier, if a projection in a struct field
            // normalizes to an opaque type, then it will reach this branch.
            ty::Opaque(..) => FfiUnsafe {
                ty,
                reason: fluent::lint::improper_ctypes_opaque,
                help: None,
            },

            // `extern "C" fn` functions can have type parameters, which may or may not be FFI-safe,
            //  so they are currently ignored for the purposes of this lint.
            ty::Param(..) | ty::Projection(..) if matches!(self.mode, CItemKind::Definition) => {
                FfiSafe
            }

            ty::Param(..)
            | ty::Projection(..)
            | ty::Infer(..)
            | ty::Bound(..)
            | ty::Error(_)
            | ty::Closure(..)
            | ty::Generator(..)
            | ty::GeneratorWitness(..)
            | ty::Placeholder(..)
            | ty::FnDef(..) => panic!("unexpected type in foreign function: {:?}", ty),
        }
    }

    fn emit_ffi_unsafe_type_lint(
        &mut self,
        ty: Ty<'tcx>,
        sp: Span,
        _note: DiagnosticMessage,
        _help: Option<DiagnosticMessage>,
    ) {
        let kind: &'tcx TyKind<'tcx> = ty.kind();
        let discriminant = tykind_discriminant(kind);
        let tyctx = self.cx.tcx;
        let sess = tyctx.sess;
        let parse_sess = &sess.parse_sess;
        let source_map = &(*parse_sess).source_map();
        let obj_rep = ObservedImproperType {
            discriminant: discriminant,
            str_rep: format!("{}", ty).to_string(),
            location: source_map.span_to_diagnostic_string(sp)
        };
        self.errors.append(&mut vec![obj_rep]);
    }

    fn check_for_opaque_ty(&mut self, sp: Span, ty: Ty<'tcx>) -> bool {
        struct ProhibitOpaqueTypes<'a, 'tcx> {
            cx: &'a LateContext<'tcx>,
        }

        impl<'a, 'tcx> ty::visit::TypeVisitor<'tcx> for ProhibitOpaqueTypes<'a, 'tcx> {
            type BreakTy = Ty<'tcx>;

            fn visit_ty(&mut self, ty: Ty<'tcx>) -> ControlFlow<Self::BreakTy> {
                match ty.kind() {
                    ty::Opaque(..) => ControlFlow::Break(ty),
                    // Consider opaque types within projections FFI-safe if they do not normalize
                    // to more opaque types.
                    ty::Projection(..) => {
                        let ty = self.cx.tcx.normalize_erasing_regions(self.cx.param_env, ty);

                        // If `ty` is an opaque type directly then `super_visit_with` won't invoke
                        // this function again.
                        if ty.has_opaque_types() {
                            self.visit_ty(ty)
                        } else {
                            ControlFlow::CONTINUE
                        }
                    }
                    _ => ty.super_visit_with(self),
                }
            }
        }

        if let Some(ty) = ty
            .visit_with(&mut ProhibitOpaqueTypes { cx: self.cx })
            .break_value()
        {
            self.emit_ffi_unsafe_type_lint(ty, sp, fluent::lint::improper_ctypes_opaque, None);
            true
        } else {
            false
        }
    }

    fn check_type_for_ffi_and_report_errors(
        &mut self,
        sp: Span,
        ty: Ty<'tcx>,
        is_static: bool,
        is_return_type: bool,
    ) {
        // We have to check for opaque types before `normalize_erasing_regions`,
        // which will replace opaque types with their underlying concrete type.
        if self.check_for_opaque_ty(sp, ty) {
            // We've already emitted an error due to an opaque type.
            return;
        }

        // it is only OK to use this function because extern fns cannot have
        // any generic types right now:
        let ty = self.cx.tcx.normalize_erasing_regions(self.cx.param_env, ty);

        // C doesn't really support passing arrays by value - the only way to pass an array by value
        // is through a struct. So, first test that the top level isn't an array, and then
        // recursively check the types inside.
        if !is_static && self.check_for_array_ty(sp, ty) {
            return;
        }

        // Don't report FFI errors for unit return types. This check exists here, and not in
        // `check_foreign_fn` (where it would make more sense) so that normalization has definitely
        // happened.
        if is_return_type && ty.is_unit() {
            return;
        }

        match self.check_type_for_ffi(&mut FxHashSet::default(), ty) {
            FfiResult::FfiSafe => {}
            FfiResult::FfiPhantom(ty) => {
                self.emit_ffi_unsafe_type_lint(
                    ty,
                    sp,
                    fluent::lint::improper_ctypes_only_phantomdata,
                    None,
                );
            }
            // If `ty` is a `repr(transparent)` newtype, and the non-zero-sized type is a generic
            // argument, which after substitution, is `()`, then this branch can be hit.
            FfiResult::FfiUnsafe { ty, .. } if is_return_type && ty.is_unit() => {}
            FfiResult::FfiUnsafe { ty, reason, help } => {
                self.emit_ffi_unsafe_type_lint(ty, sp, reason, help);
            }
        }
    }

    fn check_foreign_fn(&mut self, id: hir::HirId, decl: &hir::FnDecl<'_>) {
        let def_id = self.cx.tcx.hir().local_def_id(id);
        let sig = self.cx.tcx.fn_sig(def_id);
        let sig = self.cx.tcx.erase_late_bound_regions(sig);

        for (input_ty, input_hir) in iter::zip(sig.inputs(), decl.inputs) {
            self.check_type_for_ffi_and_report_errors(input_hir.span, *input_ty, false, false);
        }

        if let hir::FnRetTy::Return(ref ret_hir) = decl.output {
            let ret_ty = sig.output();
            self.check_type_for_ffi_and_report_errors(ret_hir.span, ret_ty, false, true);
        }
    }

    fn check_foreign_static(&mut self, id: hir::HirId, span: Span) {
        let def_id = self.cx.tcx.hir().local_def_id(id);
        let ty = self.cx.tcx.type_of(def_id);
        self.check_type_for_ffi_and_report_errors(span, ty, true, false);
    }

    fn is_internal_abi(&self, abi: SpecAbi) -> bool {
        matches!(
            abi,
            SpecAbi::Rust | SpecAbi::RustCall | SpecAbi::RustIntrinsic | SpecAbi::PlatformIntrinsic
        )
    }
}

impl<'tcx> LateLintPass<'tcx> for FfickleLate {
    fn check_fn(
        &mut self,
        cx: &LateContext<'tcx>,
        kind: hir::intravisit::FnKind<'tcx>,
        decl: &'tcx hir::FnDecl<'_>,
        _: &'tcx hir::Body<'_>,
        _: Span,
        hir_id: hir::HirId,
    ) {
        use hir::intravisit::FnKind;

        let abi: rustc_target::spec::abi::Abi = match kind {
            FnKind::ItemFn(_, _, header, ..) => header.abi,
            FnKind::Method(_, sig, ..) => sig.header.abi,
            _ => return,
        };
        let mut error_collection = vec![];
        let mut vis = ImproperCTypesVisitor {
            cx,
            mode: CItemKind::Definition,
            errors: &mut error_collection,
        };
        if !vis.is_internal_abi(abi) {
            vis.check_foreign_fn(hir_id, decl);
            self.record_errors(
                error_collection,
                format!("{}", abi).as_str(),
                ForeignItemType::RustFn,
            );
        }
    }
    fn check_foreign_item(&mut self, cx: &LateContext<'_>, it: &hir::ForeignItem<'_>) {
        let mut error_collection = vec![];
        let mut vis = ImproperCTypesVisitor {
            cx,
            mode: CItemKind::Declaration,
            errors: &mut error_collection,
        };
        let abi = cx.tcx.hir().get_foreign_abi(it.hir_id());
        if !vis.is_internal_abi(abi) {
            let item_type = match it.kind {
                hir::ForeignItemKind::Fn(ref decl, _, _) => {
                    vis.check_foreign_fn(it.hir_id(), decl);
                    Some(ForeignItemType::ForeignFn)
                }
                hir::ForeignItemKind::Static(ref ty, _) => {
                    vis.check_foreign_static(it.hir_id(), ty.span);
                    Some(ForeignItemType::StaticItem)
                }
                hir::ForeignItemKind::Type => None,
            };

            match item_type {
                Some(tp) => {
                    self.record_errors(error_collection, format!("{}", abi).as_str(), tp);
                }
                None => {}
            }
        }
    }

    fn check_crate_post(&mut self, _: &LateContext<'tcx>) {
        match serde_json::to_string(&self) {
            Ok(serialized) => match std::fs::File::create("ffickle_late.json") {
                Ok(mut fl) => match fl.write_all(serialized.as_bytes()) {
                    Ok(..) => {}
                    Err(e) => {
                        println!("Failed to write to ffickle.json: {}", e.to_string());
                        std::process::exit(1);
                    }
                },
                Err(e) => {
                    println!("Failed to open file to store analysis: {}", e.to_string());
                    std::process::exit(1);
                }
            },
            Err(e) => {
                println!(
                    "Failed to serialize Late analysis results: {}",
                    e.to_string()
                );
                std::process::exit(1);
            }
        }
    }
}

#[test]
fn ui() {
    dylint_testing::ui_test(
        env!("CARGO_PKG_NAME"),
        &std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("ui"),
    );
}

const fn tykind_discriminant<I: rustc_type_ir::Interner>(
    value: &rustc_type_ir::TyKind<I>,
) -> usize {
    match value {
        rustc_type_ir::TyKind::Bool => 0,
        rustc_type_ir::TyKind::Char => 1,
        rustc_type_ir::TyKind::Int(_) => 2,
        rustc_type_ir::TyKind::Uint(_) => 3,
        rustc_type_ir::TyKind::Float(_) => 4,
        rustc_type_ir::TyKind::Adt(_, _) => 5,
        rustc_type_ir::TyKind::Foreign(_) => 6,
        rustc_type_ir::TyKind::Str => 7,
        rustc_type_ir::TyKind::Array(_, _) => 8,
        rustc_type_ir::TyKind::Slice(_) => 9,
        rustc_type_ir::TyKind::RawPtr(_) => 10,
        rustc_type_ir::TyKind::Ref(_, _, _) => 11,
        rustc_type_ir::TyKind::FnDef(_, _) => 12,
        rustc_type_ir::TyKind::FnPtr(_) => 13,
        rustc_type_ir::TyKind::Dynamic(..) => 14,
        rustc_type_ir::TyKind::Closure(_, _) => 15,
        rustc_type_ir::TyKind::Generator(_, _, _) => 16,
        rustc_type_ir::TyKind::GeneratorWitness(_) => 17,
        rustc_type_ir::TyKind::Never => 18,
        rustc_type_ir::TyKind::Tuple(_) => 19,
        rustc_type_ir::TyKind::Projection(_) => 20,
        rustc_type_ir::TyKind::Opaque(_, _) => 21,
        rustc_type_ir::TyKind::Param(_) => 22,
        rustc_type_ir::TyKind::Bound(_, _) => 23,
        rustc_type_ir::TyKind::Placeholder(_) => 24,
        rustc_type_ir::TyKind::Infer(_) => 25,
        rustc_type_ir::TyKind::Error(_) => 26,
    }
}
