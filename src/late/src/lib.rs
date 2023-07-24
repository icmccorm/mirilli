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
use crate::hir::intravisit::FnKind;
use crate::rustc_lint::LintContext;
use crate::rustc_middle::ty::TypeVisitableExt;
use rustc_data_structures::fx::FxHashSet;
use rustc_hir as hir;
use rustc_hir::def_id::LocalDefId;
use rustc_middle::ty::layout::{LayoutOf, SizeSkeleton};
use rustc_middle::ty::subst::SubstsRef;
use rustc_middle::ty::TyKind;
use rustc_middle::ty::{self, AdtKind, Ty, TyCtxt, TypeSuperVisitable, TypeVisitable};
use rustc_session::Session;
use rustc_span::symbol::sym;
use rustc_span::Span;
use rustc_target::abi::{Abi, WrappingRange};
use serde::{Deserialize, Serialize};
use shared::*;
use std::collections::HashMap;
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
    reason: i32,
    desc: String,
}

#[derive(PartialEq, Eq, Default, Serialize, Deserialize, Hash)]
struct ForeignTypeError {
    discriminant: usize,
    str_rep: String,
    abi: String,
    reason: i32,
}

#[derive(Serialize, Deserialize, Eq, PartialEq, Hash, Clone, Copy)]
enum ForeignItemType {
    RustABIFn,
    ForeignABIFn,
    StaticItem,
    FieldDef,
    AliasTy,
}

#[derive(Default, Serialize, Deserialize)]
struct FfickleLate {
    error_id_count: usize,
    error_id_map: HashMap<usize, ForeignTypeError>,
    foreign_functions: ErrorCount,
    static_items: ErrorCount,
    field_defs: ErrorCount,
    alias_tys: ErrorCount,
    rust_functions: ErrorCount,
    decl_lint_disabled_for_crate: bool,
    defn_lint_disabled_for_crate: bool,
}

#[derive(Default, Serialize, Deserialize)]
struct ItemErrorCounts {
    counts: HashMap<usize, usize>,
    locations: HashMap<usize, Vec<String>>,
    index: usize,
    ignored: bool,
}

#[derive(Default, Serialize, Deserialize, PartialEq, Eq, Hash)]
struct ErrorLocation {
    str_rep: String,
    ignored: bool,
}

#[derive(Default, Serialize, Deserialize)]
struct ErrorCount {
    total_items: usize,
    item_error_counts: Vec<ItemErrorCounts>,
    abis: HashMap<String, Vec<String>>,
}

trait ErrorIDStore {
    fn record_errors(
        &mut self,
        errors: Vec<ObservedImproperType>,
        abi_string: &str,
        item_type: ForeignItemType,
        were_ignored: bool,
    ) -> ();

    fn record_abi(
        &mut self,
        abi_string: &str,
        item_type: ForeignItemType,
        sp: Span,
        sess: &Session,
    ) -> ();
}

impl ErrorIDStore for FfickleLate {
    fn record_abi<'tcx>(
        &mut self,
        abi_string: &str,
        item_type: ForeignItemType,
        sp: Span,
        sess: &Session,
    ) -> () {
        let store = match item_type {
            ForeignItemType::RustABIFn => &mut self.rust_functions,
            ForeignItemType::ForeignABIFn => &mut self.foreign_functions,
            ForeignItemType::StaticItem => &mut self.static_items,
            ForeignItemType::FieldDef => &mut self.field_defs,
            ForeignItemType::AliasTy => &mut self.alias_tys,
        };
        (store.abis)
            .entry(abi_string.to_string())
            .and_modify(|e| e.extend(vec![span_to_string(sp, sess)]))
            .or_insert(vec![span_to_string(sp, sess)]);
    }
    fn record_errors<'tcx>(
        &mut self,
        errors: Vec<ObservedImproperType>,
        abi_string: &str,
        item_type: ForeignItemType,
        were_ignored: bool,
    ) -> () {
        let store = match item_type {
            ForeignItemType::RustABIFn => &mut self.rust_functions,
            ForeignItemType::ForeignABIFn => &mut self.foreign_functions,
            ForeignItemType::StaticItem => &mut self.static_items,
            ForeignItemType::FieldDef => &mut self.field_defs,
            ForeignItemType::AliasTy => &mut self.alias_tys,
        };
        let mut err_counts = ItemErrorCounts::default();
        err_counts.index = (*store).total_items;
        err_counts.ignored = were_ignored;
        (*store).total_items += 1;

        for err in errors {
            let foreign_err = ForeignTypeError {
                discriminant: err.discriminant,
                str_rep: err.str_rep,
                abi: abi_string.to_string().replace('\"', ""),
                reason: err.reason,
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
            err_counts
                .locations
                .entry(id)
                .or_default()
                .extend(vec![err.location]);
            let count = (err_counts).counts.entry(id).or_insert(0);
            *count += 1;
        }
        if !err_counts.counts.is_empty() {
            (*store).item_error_counts.extend(vec![err_counts]);
        }
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
    FfiUnsafe { ty: Ty<'tcx>, reason: Reason },
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
        let field_ty = tcx.type_of(field.did).subst_identity();
        let is_zst = tcx
            .layout_of(param_env.and(field_ty))
            .is_ok_and(|layout| layout.is_zst());
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
        ty::Int(ty) => Ty::new_int(tcx, ty),
        ty::Uint(ty) => Ty::new_uint(tcx, ty),
        ty::RawPtr(ty_mut) => Ty::new_ptr(tcx, ty_mut),
        // As these types are always non-null, the nullable equivalent of
        // Option<T> of these types are their raw pointer counterparts.
        ty::Ref(_region, ty, mutbl) => Ty::new_ptr(tcx, ty::TypeAndMut { ty, mutbl }),
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
            [var_one, var_two] => match (&var_one.fields.raw[..], &var_two.fields.raw[..]) {
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
            self.emit_ffi_unsafe_type_lint(ty, sp, Reason::Array);
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

        let transparent_safety = def.repr().transparent().then(|| {
            // Can assume that at most one field is not a ZST, so only check
            // that field's type for FFI-safety.
            if let Some(field) = transparent_newtype_field(self.cx.tcx, variant) {
                return self.check_field_type_for_ffi(cache, field, substs);
            } else {
                // All fields are ZSTs; this means that the type should behave
                // like (), which is FFI-unsafe... except if all fields are PhantomData,
                // which is tested for below
                FfiUnsafe {
                    ty,
                    reason: Reason::StructZeroSized,
                }
            }
        });
        // We can't completely trust repr(C) markings; make sure the fields are
        // actually safe.
        let mut all_phantom = !variant.fields.is_empty();
        for field in &variant.fields {
            match self.check_field_type_for_ffi(cache, &field, substs) {
                FfiSafe => {
                    all_phantom = false;
                }
                FfiPhantom(..) if !def.repr().transparent() && def.is_enum() => {
                    return FfiUnsafe {
                        ty,
                        reason: Reason::EnumPhantomData,
                    };
                }
                FfiPhantom(..) => {}
                r => return transparent_safety.unwrap_or(r),
            }
        }

        if all_phantom {
            FfiPhantom(ty)
        } else {
            transparent_safety.unwrap_or(FfiSafe)
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
                    if ty.boxed_ty().is_sized(tcx, self.cx.param_env) {
                        return FfiSafe;
                    } else {
                        return FfiUnsafe {
                            ty,
                            reason: Reason::Box,
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
                                    Reason::StructLayout
                                } else {
                                    Reason::UnionLayout
                                },
                            };
                        }

                        let is_non_exhaustive =
                            def.non_enum_variant().is_field_list_non_exhaustive();
                        if is_non_exhaustive && !def.did().is_local() {
                            return FfiUnsafe {
                                ty,
                                reason: if def.is_struct() {
                                    Reason::StructNonExhaustive
                                } else {
                                    Reason::UnionNonExhaustive
                                },
                            };
                        }

                        if def.non_enum_variant().fields.is_empty() {
                            return FfiUnsafe {
                                ty,
                                reason: if def.is_struct() {
                                    Reason::StructFieldless
                                } else {
                                    Reason::UnionFieldless
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
                                    reason: Reason::EnumNoRepresentation,
                                };
                            }
                        }

                        if def.is_variant_list_non_exhaustive() && !def.did().is_local() {
                            return FfiUnsafe {
                                ty,
                                reason: Reason::EnumNonExhaustive,
                            };
                        }

                        // Check the contained variants.
                        for variant in def.variants() {
                            let is_non_exhaustive = variant.is_field_list_non_exhaustive();
                            if is_non_exhaustive && !variant.def_id.is_local() {
                                return FfiUnsafe {
                                    ty,
                                    reason: Reason::EnumNonExhaustiveVariant,
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
                reason: Reason::Char,
            },

            ty::Int(ty::IntTy::I128) | ty::Uint(ty::UintTy::U128) => FfiUnsafe {
                ty,
                reason: Reason::Num128Bit,
            },

            // Primitive types with a stable representation.
            ty::Bool | ty::Int(..) | ty::Uint(..) | ty::Float(..) | ty::Never => FfiSafe,

            ty::Slice(_) => FfiUnsafe {
                ty,
                reason: Reason::Slice,
            },

            ty::Dynamic(..) => FfiUnsafe {
                ty,
                reason: Reason::Dyn,
            },

            ty::Str => FfiUnsafe {
                ty,
                reason: Reason::Str,
            },

            ty::Tuple(..) => FfiUnsafe {
                ty,
                reason: Reason::Tuple,
            },

            ty::RawPtr(ty::TypeAndMut { ty, .. }) | ty::Ref(_, ty, _)
                if {
                    matches!(self.mode, CItemKind::Definition)
                        && ty.is_sized(self.cx.tcx, self.cx.param_env)
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
                if is_internal_abi(sig.abi()) {
                    return FfiUnsafe {
                        ty,
                        reason: Reason::FnPtr,
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
            ty::Alias(ty::Opaque, ..) => FfiUnsafe {
                ty,
                reason: Reason::Opaque,
            },

            // `extern "C" fn` functions can have type parameters, which may or may not be FFI-safe,
            //  so they are currently ignored for the purposes of this lint.
            ty::Param(..) | ty::Alias(ty::Projection | ty::Inherent, ..)
                if matches!(self.mode, CItemKind::Definition) =>
            {
                FfiSafe
            }

            ty::Param(..)
            | ty::Alias(ty::Projection | ty::Inherent | ty::Weak, ..)
            | ty::Infer(..)
            | ty::Bound(..)
            | ty::Error(_)
            | ty::Closure(..)
            | ty::Generator(..)
            | ty::GeneratorWitness(..)
            | ty::GeneratorWitnessMIR(..)
            | ty::Placeholder(..)
            | ty::FnDef(..) => panic!("unexpected type in foreign function: {:?}", ty),
        }
    }

    fn emit_ffi_unsafe_type_lint(&mut self, ty: Ty<'tcx>, sp: Span, reason: Reason) {
        let desc = match self.mode {
            CItemKind::Declaration => "block",
            CItemKind::Definition => "fn",
        };
        let kind: &'tcx TyKind<'tcx> = ty.kind();
        let discriminant = tykind_discriminant(kind);
        let sess = self.cx.sess();
        let parse_sess = &sess.parse_sess;
        let source_map = &(*parse_sess).source_map();
        let obj_rep = ObservedImproperType {
            discriminant: discriminant,
            str_rep: format!("{}", ty).to_string(),
            location: source_map.span_to_diagnostic_string(sp),
            reason: reason as i32,
            desc: desc.to_string(),
        };
        self.errors.append(&mut vec![obj_rep]);
    }

    fn check_for_opaque_ty(&mut self, sp: Span, ty: Ty<'tcx>) -> bool {
        struct ProhibitOpaqueTypes;
        impl<'tcx> ty::visit::TypeVisitor<TyCtxt<'tcx>> for ProhibitOpaqueTypes {
            type BreakTy = Ty<'tcx>;

            fn visit_ty(&mut self, ty: Ty<'tcx>) -> ControlFlow<Self::BreakTy> {
                if !ty.has_opaque_types() {
                    return ControlFlow::Continue(());
                }

                if let ty::Alias(ty::Opaque, ..) = ty.kind() {
                    ControlFlow::Break(ty)
                } else {
                    ty.super_visit_with(self)
                }
            }
        }

        if let Some(ty) = self
            .cx
            .tcx
            .normalize_erasing_regions(self.cx.param_env, ty)
            .visit_with(&mut ProhibitOpaqueTypes)
            .break_value()
        {
            self.emit_ffi_unsafe_type_lint(ty, sp, Reason::Opaque);
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
                self.emit_ffi_unsafe_type_lint(ty, sp, Reason::OnlyPhantomData);
            }
            // If `ty` is a `repr(transparent)` newtype, and the non-zero-sized type is a generic
            // argument, which after substitution, is `()`, then this branch can be hit.
            FfiResult::FfiUnsafe { ty, .. } if is_return_type && ty.is_unit() => {}
            FfiResult::FfiUnsafe { ty, reason } => {
                self.emit_ffi_unsafe_type_lint(ty, sp, reason);
            }
        }
    }
    /// Check if a function's argument types and result type are "ffi-safe".
    ///
    /// For a external ABI function, argument types and the result type are walked to find fn-ptr
    /// types that have external ABIs, as these still need checked.
    fn check_fn_helper(&mut self, def_id: LocalDefId, decl: &'tcx hir::FnDecl<'_>) {
        let sig = self.cx.tcx.fn_sig(def_id).subst_identity();
        let sig = self.cx.tcx.erase_late_bound_regions(sig);

        for (input_ty, input_hir) in iter::zip(sig.inputs(), decl.inputs) {
            for (fn_ptr_ty, span) in self.find_fn_ptr_ty_with_external_abi(input_hir, *input_ty) {
                self.check_type_for_ffi_and_report_errors(span, fn_ptr_ty, false, false);
            }
        }

        if let hir::FnRetTy::Return(ref ret_hir) = decl.output {
            for (fn_ptr_ty, span) in self.find_fn_ptr_ty_with_external_abi(ret_hir, sig.output()) {
                self.check_type_for_ffi_and_report_errors(span, fn_ptr_ty, false, true);
            }
        }
    }

    /// Check if a function's argument types and result type are "ffi-safe".
    fn check_foreign_fn_helper(&mut self, def_id: LocalDefId, decl: &'tcx hir::FnDecl<'_>) {
        let sig = self.cx.tcx.fn_sig(def_id).subst_identity();
        let sig = self.cx.tcx.erase_late_bound_regions(sig);

        for (input_ty, input_hir) in iter::zip(sig.inputs(), decl.inputs) {
            self.check_type_for_ffi_and_report_errors(input_hir.span, *input_ty, false, false);
        }

        if let hir::FnRetTy::Return(ref ret_hir) = decl.output {
            self.check_type_for_ffi_and_report_errors(ret_hir.span, sig.output(), false, true);
        }
    }

    fn check_foreign_static_helper(&mut self, id: hir::OwnerId, span: Span) {
        let ty = self.cx.tcx.type_of(id).subst_identity();
        self.check_type_for_ffi_and_report_errors(span, ty, true, false);
    }

    /// Find any fn-ptr types with external ABIs in `ty`.
    ///
    /// For example, `Option<extern "C" fn()>` returns `extern "C" fn()`
    fn find_fn_ptr_ty_with_external_abi(
        &self,
        hir_ty: &hir::Ty<'tcx>,
        ty: Ty<'tcx>,
    ) -> Vec<(Ty<'tcx>, Span)> {
        struct FnPtrFinder<'parent, 'a, 'tcx> {
            _visitor: &'parent ImproperCTypesVisitor<'a, 'tcx>,
            spans: Vec<Span>,
            tys: Vec<Ty<'tcx>>,
        }

        impl<'parent, 'a, 'tcx> hir::intravisit::Visitor<'_> for FnPtrFinder<'parent, 'a, 'tcx> {
            fn visit_ty(&mut self, ty: &'_ hir::Ty<'_>) {
                if let hir::TyKind::BareFn(hir::BareFnTy { abi, .. }) = ty.kind {
                    if !is_internal_abi(*abi) {
                        self.spans.push(ty.span);
                    }
                }

                hir::intravisit::walk_ty(self, ty)
            }
        }

        impl<'vis, 'a, 'tcx> ty::visit::TypeVisitor<TyCtxt<'tcx>> for FnPtrFinder<'vis, 'a, 'tcx> {
            type BreakTy = Ty<'tcx>;

            fn visit_ty(&mut self, ty: Ty<'tcx>) -> ControlFlow<Self::BreakTy> {
                if let ty::FnPtr(sig) = ty.kind() {
                    if !is_internal_abi(sig.abi()) {
                        self.tys.push(ty);
                    }
                }
                ty.super_visit_with(self)
            }
        }

        let mut visitor = FnPtrFinder {
            _visitor: &*self,
            spans: Vec::new(),
            tys: Vec::new(),
        };
        ty.visit_with(&mut visitor);
        hir::intravisit::Visitor::visit_ty(&mut visitor, hir_ty);

        iter::zip(visitor.tys.drain(..), visitor.spans.drain(..)).collect()
    }
}

fn lint_disabled<'tcx>(cx: &LateContext<'tcx>, name: &str) -> bool {
    let lint_store = cx.lint_store;
    let all_lints = lint_store.get_lints();
    let lint = (*all_lints).iter().find(|l| l.name == name).unwrap();
    cx.get_lint_level(lint).eq(&rustc_lint::Level::Allow)
}

impl FfickleLate {
    fn check_ty_maybe_containing_foreign_fnptr<'tcx>(
        &mut self,
        cx: &LateContext<'tcx>,
        hir_ty: &'tcx hir::Ty<'_>,
        ty: Ty<'tcx>,
        item_type: ForeignItemType,
    ) {
        let abi = cx.tcx.hir().get_foreign_abi(hir_ty.hir_id);
        let mut error_collection = vec![];
        let mut vis = ImproperCTypesVisitor {
            cx,
            mode: CItemKind::Definition,
            errors: &mut error_collection,
        };
        for (fn_ptr_ty, span) in vis.find_fn_ptr_ty_with_external_abi(hir_ty, ty) {
            vis.check_type_for_ffi_and_report_errors(span, fn_ptr_ty, true, false);
        }
        let were_ignored = lint_disabled(cx, "IMPROPER_CTYPES");
        self.record_errors(
            error_collection,
            format!("{}", abi).as_str(),
            item_type,
            were_ignored,
        );
    }
}

impl<'tcx> LateLintPass<'tcx> for FfickleLate {
    fn check_crate(&mut self, cx: &LateContext<'tcx>) {
        self.decl_lint_disabled_for_crate = lint_disabled(cx, "IMPROPER_CTYPES");
        self.defn_lint_disabled_for_crate = lint_disabled(cx, "IMPROPER_CTYPES_DEFINITIONS")
    }

    fn check_fn(
        &mut self,
        cx: &LateContext<'tcx>,
        kind: hir::intravisit::FnKind<'tcx>,
        decl: &'tcx hir::FnDecl<'_>,
        _: &'tcx hir::Body<'_>,
        sp: Span,
        id: LocalDefId,
    ) {
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

        let abi_type = if is_internal_abi(abi) {
            vis.check_fn_helper(id, decl);
            ForeignItemType::RustABIFn
        } else {
            vis.check_foreign_fn_helper(id, decl);
            ForeignItemType::ForeignABIFn
        };
        if !is_internal_abi(abi) {
            self.record_abi(abi.name(), abi_type, sp, cx.sess());
        }
        if error_collection.len() > 0 {
            let were_ignored = lint_disabled(cx, "IMPROPER_CTYPES_DEFINITIONS");
            self.record_errors(
                error_collection,
                format!("{}", abi).as_str(),
                abi_type,
                were_ignored,
            );
        }
    }

    fn check_item(&mut self, cx: &LateContext<'tcx>, item: &'tcx hir::Item<'tcx>) {
        match item.kind {
            hir::ItemKind::Static(ty, ..)
            | hir::ItemKind::Const(ty, ..)
            | hir::ItemKind::TyAlias(ty, ..) => {
                self.check_ty_maybe_containing_foreign_fnptr(
                    cx,
                    ty,
                    cx.tcx.type_of(item.owner_id).subst_identity(),
                    ForeignItemType::AliasTy,
                );
            }
            // See `check_fn`..
            hir::ItemKind::Fn(..) => {}
            // See `check_field_def`..
            hir::ItemKind::Union(..) | hir::ItemKind::Struct(..) | hir::ItemKind::Enum(..) => {}
            // Doesn't define something that can contain a external type to be checked.
            hir::ItemKind::Impl(..)
            | hir::ItemKind::TraitAlias(..)
            | hir::ItemKind::Trait(..)
            | hir::ItemKind::OpaqueTy(..)
            | hir::ItemKind::GlobalAsm(..)
            | hir::ItemKind::ForeignMod { .. }
            | hir::ItemKind::Mod(..)
            | hir::ItemKind::Macro(..)
            | hir::ItemKind::Use(..)
            | hir::ItemKind::ExternCrate(..) => {}
        }
    }

    fn check_field_def(&mut self, cx: &LateContext<'tcx>, field: &'tcx hir::FieldDef<'tcx>) {
        self.check_ty_maybe_containing_foreign_fnptr(
            cx,
            field.ty,
            cx.tcx.type_of(field.def_id).subst_identity(),
            ForeignItemType::FieldDef,
        );
    }

    fn check_foreign_item(&mut self, cx: &LateContext<'tcx>, it: &hir::ForeignItem<'tcx>) {
        let abi = cx.tcx.hir().get_foreign_abi(it.hir_id());
        let mut error_collection = vec![];
        let mut vis = ImproperCTypesVisitor {
            cx,
            mode: CItemKind::Declaration,
            errors: &mut error_collection,
        };

        let item_type = match it.kind {
            hir::ForeignItemKind::Fn(ref decl, _, _) if !is_internal_abi(abi) => {
                vis.check_foreign_fn_helper(it.owner_id.def_id, decl);
                Some(ForeignItemType::ForeignABIFn)
            }
            hir::ForeignItemKind::Static(ref ty, _) if !is_internal_abi(abi) => {
                vis.check_foreign_static_helper(it.owner_id, ty.span);
                Some(ForeignItemType::StaticItem)
            }
            hir::ForeignItemKind::Fn(ref decl, _, _) => {
                vis.check_fn_helper(it.owner_id.def_id, decl);
                Some(ForeignItemType::RustABIFn)
            }
            hir::ForeignItemKind::Static(..) | hir::ForeignItemKind::Type => None,
        };
        match item_type {
            Some(tp) => {
                if !is_internal_abi(abi) {
                    self.record_abi(abi.name(), tp, it.span, cx.sess());
                }
                let were_ignored = lint_disabled(cx, "IMPROPER_CTYPES");
                self.record_errors(
                    error_collection,
                    format!("{}", abi).as_str(),
                    tp,
                    were_ignored,
                );
            }
            None => {}
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
#[repr(i32)]
#[derive(PartialEq, Eq, PartialOrd, Ord, Hash)]
enum Reason {
    Opaque = 0,
    FnPtr,
    Tuple,
    Str,
    Dyn,
    Slice,
    Num128Bit,
    Char,
    EnumNonExhaustive,
    EnumNonExhaustiveVariant,
    EnumNoRepresentation,
    StructFieldless,
    UnionFieldless,
    StructNonExhaustive,
    UnionNonExhaustive,
    UnionLayout,
    StructLayout,
    Box,
    EnumPhantomData,
    StructZeroSized,
    Array,
    OnlyPhantomData,
}

const fn tykind_discriminant(value: &rustc_middle::ty::TyKind) -> usize {
    match value {
        rustc_middle::ty::TyKind::Bool => 0,
        rustc_middle::ty::TyKind::Char => 1,
        rustc_middle::ty::TyKind::Int(_) => 2,
        rustc_middle::ty::TyKind::Uint(_) => 3,
        rustc_middle::ty::TyKind::Float(_) => 4,
        rustc_middle::ty::TyKind::Adt(_, _) => 5,
        rustc_middle::ty::TyKind::Foreign(_) => 6,
        rustc_middle::ty::TyKind::Str => 7,
        rustc_middle::ty::TyKind::Array(_, _) => 8,
        rustc_middle::ty::TyKind::Slice(_) => 9,
        rustc_middle::ty::TyKind::RawPtr(_) => 10,
        rustc_middle::ty::TyKind::Ref(_, _, _) => 11,
        rustc_middle::ty::TyKind::FnDef(_, _) => 12,
        rustc_middle::ty::TyKind::FnPtr(_) => 13,
        rustc_middle::ty::TyKind::Dynamic(..) => 14,
        rustc_middle::ty::TyKind::Closure(_, _) => 15,
        rustc_middle::ty::TyKind::Generator(_, _, _) => 16,
        rustc_middle::ty::TyKind::GeneratorWitness(_) => 17,
        rustc_middle::ty::TyKind::Never => 18,
        rustc_middle::ty::TyKind::Tuple(_) => 19,
        rustc_type_ir::TyKind::Alias(_, _) => 20,
        rustc_middle::ty::TyKind::Param(_) => 21,
        rustc_middle::ty::TyKind::Bound(_, _) => 22,
        rustc_middle::ty::TyKind::Placeholder(_) => 23,
        rustc_middle::ty::TyKind::Infer(_) => 24,
        rustc_middle::ty::TyKind::Error(_) => 25,
        rustc_type_ir::TyKind::GeneratorWitnessMIR(_, _) => 26,
    }
}
