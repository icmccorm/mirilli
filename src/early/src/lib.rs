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
use crate::rustc_lint::LintContext;
use rustc_ast::ast;
use rustc_ast::visit::FnKind;
use rustc_ast::Extern::Explicit;
use rustc_span::Span;
use rustc_target::spec::abi::lookup;
use serde::{Deserialize, Serialize};
use shared::*;
use std::collections::HashMap;
use std::io::Write;

dylint_linting::impl_early_lint! {
    pub FFICKLE_EARLY,
    Warn,
    "description goes here",
    FfickleEarly::default()
}
use rustc_lint::{EarlyContext, EarlyLintPass};

#[derive(Default, Serialize, Deserialize)]

struct FfickleEarly {
    foreign_function_abis: HashMap<String, Vec<String>>,
    static_item_abis: HashMap<String, Vec<String>>,
    rust_function_abis: HashMap<String, Vec<String>>,
    unknown_abis: Vec<String>,
}

impl EarlyLintPass for FfickleEarly {
    fn check_fn(&mut self, cx: &EarlyContext<'_>, kind: FnKind, _: Span, _: ast::NodeId) {
        if let FnKind::Fn(_, _, sig, ..) = kind {
            if let Explicit(sl, _) = sig.header.ext {
                let session = &cx.sess();
                let abi_string = sl.symbol_unescaped.as_str().to_string().replace('\"', "");
                match lookup(&abi_string) {
                    Some(abi) => {
                        if !is_internal_abi(abi) {
                            self.rust_function_abis
                                .entry(abi_string.to_string())
                                .and_modify(|e| e.extend(vec![span_to_string(sig.span, session)]))
                                .or_insert(vec![span_to_string(sig.span, session)]);
                        }
                    }
                    None => self.unknown_abis.extend(vec![abi_string]),
                }
            }
        }
    }

    fn check_item(&mut self, cx: &EarlyContext<'_>, it: &ast::Item) {
        if let ast::ItemKind::ForeignMod(fm) = &it.kind {
            let fm: &ast::ForeignMod = fm;
            let abi_string = match fm.abi {
                Some(abi) => abi.symbol_unescaped.as_str().to_string().replace('\"', ""),
                None => "C".to_string(),
            };
            if !is_internal_abi(lookup(&abi_string).unwrap()) {
                let items = &fm.items;
                let session = &cx.sess();
                for item in items {
                    match item.kind {
                        rustc_ast::ast::ForeignItemKind::Fn(_) => {
                            self.foreign_function_abis
                                .entry(abi_string.to_string())
                                .and_modify(|e| e.extend(vec![span_to_string(item.span, session)]))
                                .or_insert(vec![span_to_string(item.span, session)]);
                        }
                        rustc_ast::ast::ForeignItemKind::Static(_, _, _) => {
                            self.static_item_abis
                                .entry(abi_string.to_string())
                                .and_modify(|e| e.extend(vec![span_to_string(item.span, session)]))
                                .or_insert(vec![span_to_string(item.span, session)]);
                        }
                        _ => {}
                    }
                }
            }
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
