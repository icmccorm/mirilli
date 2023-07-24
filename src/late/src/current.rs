
impl<'a, 'tcx> ImproperCTypesVisitor<'a, 'tcx> {




    /// Checks if the given `VariantDef`'s field types are "ffi-safe".


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

            ty::Int(ty::IntTy::I128) | ty::Uint(ty::UintTy::U128) =>
                FfiUnsafe {
                    ty,
                    reason: Reason::Num128Bit,
                },
            

            // Primitive types with a stable representation.
            ty::Bool | ty::Int(..) | ty::Uint(..) | ty::Float(..) | ty::Never => FfiSafe,

            ty::Slice(_) => FfiUnsafe {
                ty,
                reason: Reason::Slice,
            },

            ty::Dynamic(..) =>
                FfiUnsafe {
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
                if self.is_internal_abi(sig.abi()) {
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
            | ty::FnDef(..) => bug!("unexpected type in foreign function: {:?}", ty),
        }
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
            self.emit_ffi_unsafe_type_lint(ty, sp, fluent::lint_improper_ctypes_opaque, None);
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
                    fluent::lint_improper_ctypes_only_phantomdata,
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

    /// Check if a function's argument types and result type are "ffi-safe".
    ///
    /// For a external ABI function, argument types and the result type are walked to find fn-ptr
    /// types that have external ABIs, as these still need checked.
    fn check_fn(&mut self, def_id: LocalDefId, decl: &'tcx hir::FnDecl<'_>) {
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
    fn check_foreign_fn(&mut self, def_id: LocalDefId, decl: &'tcx hir::FnDecl<'_>) {
        let sig = self.cx.tcx.fn_sig(def_id).subst_identity();
        let sig = self.cx.tcx.erase_late_bound_regions(sig);

        for (input_ty, input_hir) in iter::zip(sig.inputs(), decl.inputs) {
            self.check_type_for_ffi_and_report_errors(input_hir.span, *input_ty, false, false);
        }

        if let hir::FnRetTy::Return(ref ret_hir) = decl.output {
            self.check_type_for_ffi_and_report_errors(ret_hir.span, sig.output(), false, true);
        }
    }

    fn check_foreign_static(&mut self, id: hir::OwnerId, span: Span) {
        let ty = self.cx.tcx.type_of(id).subst_identity();
        self.check_type_for_ffi_and_report_errors(span, ty, true, false);
    }

    fn is_internal_abi(&self, abi: SpecAbi) -> bool {
        matches!(
            abi,
            SpecAbi::Rust | SpecAbi::RustCall | SpecAbi::RustIntrinsic | SpecAbi::PlatformIntrinsic
        )
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
            visitor: &'parent ImproperCTypesVisitor<'a, 'tcx>,
            spans: Vec<Span>,
            tys: Vec<Ty<'tcx>>,
        }

        impl<'parent, 'a, 'tcx> hir::intravisit::Visitor<'_> for FnPtrFinder<'parent, 'a, 'tcx> {
            fn visit_ty(&mut self, ty: &'_ hir::Ty<'_>) {
                debug!(?ty);
                if let hir::TyKind::BareFn(hir::BareFnTy { abi, .. }) = ty.kind
                    && !self.visitor.is_internal_abi(*abi)
                {
                    self.spans.push(ty.span);
                }

                hir::intravisit::walk_ty(self, ty)
            }
        }

        impl<'vis, 'a, 'tcx> ty::visit::TypeVisitor<TyCtxt<'tcx>> for FnPtrFinder<'vis, 'a, 'tcx> {
            type BreakTy = Ty<'tcx>;

            fn visit_ty(&mut self, ty: Ty<'tcx>) -> ControlFlow<Self::BreakTy> {
                if let ty::FnPtr(sig) = ty.kind() && !self.visitor.is_internal_abi(sig.abi()) {
                    self.tys.push(ty);
                }

                ty.super_visit_with(self)
            }
        }

        let mut visitor = FnPtrFinder { visitor: &*self, spans: Vec::new(), tys: Vec::new() };
        ty.visit_with(&mut visitor);
        hir::intravisit::Visitor::visit_ty(&mut visitor, hir_ty);

        iter::zip(visitor.tys.drain(..), visitor.spans.drain(..)).collect()
    }
}

impl<'tcx> LateLintPass<'tcx> for ImproperCTypesDeclarations {
    fn check_foreign_item(&mut self, cx: &LateContext<'tcx>, it: &hir::ForeignItem<'tcx>) {
        let mut vis = ImproperCTypesVisitor { cx, mode: CItemKind::Declaration };
        let abi = cx.tcx.hir().get_foreign_abi(it.hir_id());

        match it.kind {
            hir::ForeignItemKind::Fn(ref decl, _, _) if !vis.is_internal_abi(abi) => {
                vis.check_foreign_fn(it.owner_id.def_id, decl);
            }
            hir::ForeignItemKind::Static(ref ty, _) if !vis.is_internal_abi(abi) => {
                vis.check_foreign_static(it.owner_id, ty.span);
            }
            hir::ForeignItemKind::Fn(ref decl, _, _) => vis.check_fn(it.owner_id.def_id, decl),
            hir::ForeignItemKind::Static(..) | hir::ForeignItemKind::Type => (),
        }
    }
}

impl ImproperCTypesDefinitions {
    fn check_ty_maybe_containing_foreign_fnptr<'tcx>(
        &mut self,
        cx: &LateContext<'tcx>,
        hir_ty: &'tcx hir::Ty<'_>,
        ty: Ty<'tcx>,
    ) {
        let mut vis = ImproperCTypesVisitor { cx, mode: CItemKind::Definition };
        for (fn_ptr_ty, span) in vis.find_fn_ptr_ty_with_external_abi(hir_ty, ty) {
            vis.check_type_for_ffi_and_report_errors(span, fn_ptr_ty, true, false);
        }
    }
}