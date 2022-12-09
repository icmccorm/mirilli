#![feature(rustc_private)]

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
use std::io::Write;
use rustc_ast::NestedMetaItem::MetaItem;
use rustc_span::symbol::sym;
use rustc_ast::ast;
use rustc_ast::visit::FnKind;
use rustc_ast::Extern::Explicit;
use rustc_span::Span;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

dylint_linting::impl_early_lint! {
    pub FFICKLE_EARLY,
    Warn,
    "description goes here",
    FfickleEarly::default()
}
use rustc_lint::{EarlyContext, EarlyLintPass};

#[derive(Default, Serialize, Deserialize)]

struct FfickleEarly {
    foreign_function_abis: HashMap<String, usize>,
    static_item_abis: HashMap<String, usize>,
    rust_function_abis: HashMap<String, usize>,
    foreign_module_lint_blocked: bool,
    rust_function_lint_blocked: bool,
}

impl<'tcx> EarlyLintPass for FfickleEarly {
    fn enter_lint_attrs(&mut self, _: &EarlyContext<'_>, attrs: &[ast::Attribute]) {
        for attr in attrs {
            if attr.has_name(sym::allow) {
                match attr.meta_item_list() {
                    None => {}
                    Some(l) => {
                        for item in l {
                            match item {
                                MetaItem(mi) => match mi.ident() {
                                    Some(id) => {
                                        if id.name.as_str().eq("improper_ctypes_definitions") {
                                            self.rust_function_lint_blocked = true;
                                        } else if id.name.as_str().eq("improper_ctypes") {
                                            self.foreign_module_lint_blocked = true;
                                        }
                                    }
                                    None => {}
                                },
                                _ => {}
                            }
                        }
                    }
                }
            }
        }
    }
    fn check_fn(&mut self, _: &EarlyContext<'_>, kind: FnKind<'_>, _: Span, _: ast::NodeId) {
        match kind {
            FnKind::Fn(_, _, sig, ..) => match sig.header.ext {
                Explicit(sl, _) => {
                    let abi_string = sl.symbol_unescaped.as_str().to_string().replace("\"", "");
                    self.rust_function_abis
                        .entry(abi_string.to_string())
                        .and_modify(|e| *e += 1)
                        .or_insert(1);
                }
                _ => {}
            },
            _ => {}
        };
    }

    fn check_item(&mut self, _cx: &EarlyContext<'_>, it: &ast::Item) {
        match &it.kind {
            ast::ItemKind::ForeignMod(fm) => {
                let fm: &ast::ForeignMod = fm;
                let abi_string = match fm.abi {
                    Some(abi) => abi.symbol_unescaped.as_str().to_string().replace("\"", ""),
                    None => "C".to_string(),
                };
                let items: &Vec<rustc_ast::ptr::P<rustc_ast::ast::ForeignItem>> = &fm.items;
                for item in items {
                    match item.kind {
                        rustc_ast::ast::ForeignItemKind::Fn(_) => {
                            self.foreign_function_abis
                                .entry(abi_string.to_string())
                                .and_modify(|e| *e += 1)
                                .or_insert(1);
                        }
                        rustc_ast::ast::ForeignItemKind::Static(_, _, _) => {
                            self.static_item_abis
                                .entry(abi_string.to_string())
                                .and_modify(|e| *e += 1)
                                .or_insert(1);
                        }
                        _ => {}
                    }
                }
            }
            _ => {}
        }
    }

    fn check_crate_post(&mut self, _: &EarlyContext<'_>, _: &ast::Crate) {
        match serde_json::to_string(&self) {
            Ok(serialized) => match std::fs::File::create("ffickle_early.json") {
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
                println!("Failed to serialize analysis results: {}", e.to_string());
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
