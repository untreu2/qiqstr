import re, glob, os, sys
root = sys.argv[1]
out = ["use std::sync::Arc;", "use crate::api;", "use crate::sink::{EventSink, StreamSink};", "",
"#[derive(Debug, thiserror::Error, uniffi::Error)]",
"pub enum QiqError {", "    #[error(\"{message}\")]", "    Failed { message: String },", "}", "",
"impl From<anyhow::Error> for QiqError {", "    fn from(e: anyhow::Error) -> Self { QiqError::Failed { message: format!(\"{e:#}\") } }", "}", "",
"fn runtime() -> &'static tokio::runtime::Runtime {",
"    static RT: once_cell::sync::Lazy<tokio::runtime::Runtime> = once_cell::sync::Lazy::new(|| {",
"        tokio::runtime::Builder::new_multi_thread().enable_all().thread_name(\"qiqstr-core\").build().expect(\"tokio runtime\")",
"    });", "    &RT", "}", "",
"async fn on_rt<F, T>(fut: F) -> Result<T, QiqError> where F: std::future::Future<Output = anyhow::Result<T>> + Send + 'static, T: Send + 'static {",
"    runtime().spawn(fut).await.map_err(|e| QiqError::Failed { message: e.to_string() })?.map_err(Into::into)",
"}", "",
"async fn on_rt_plain<F, T>(fut: F) -> Result<T, QiqError> where F: std::future::Future<Output = T> + Send + 'static, T: Send + 'static {",
"    runtime().spawn(fut).await.map_err(|e| QiqError::Failed { message: e.to_string() })",
"}", "",
"#[derive(uniffi::Record)]", "pub struct KeyPair { pub private_key: String, pub public_key: String }", "",
"#[derive(uniffi::Record)]", "pub struct EmbeddedIds { pub event_ids: Vec<String>, pub addresses: Vec<String> }", "",
"#[uniffi::export]", "pub fn generate_keypair() -> KeyPair { let (a, b) = api::crypto::generate_keypair(); KeyPair { private_key: a, public_key: b } }", "",
"#[uniffi::export]", "pub fn extract_embedded_ids_batch_typed(contents: Vec<String>) -> EmbeddedIds { let (a, b) = api::database::extract_embedded_ids_batch_typed(contents); EmbeddedIds { event_ids: a, addresses: b } }", "",
]
skip = {"generate_keypair", "extract_embedded_ids_batch_typed"}
for f in sorted(glob.glob(os.path.join(root, "src/api/*.rs"))):
    mod = os.path.basename(f)[:-3]
    if mod == "mod": continue
    s = open(f).read()
    for m in re.finditer(r'\npub (async )?fn (\w+)\s*\((.*?)\)\s*(?:->\s*([^{]+?))?\s*\{', s, re.S):
        is_async, name, args, ret = bool(m.group(1)), m.group(2), m.group(3), (m.group(4) or "").strip()
        if name in skip: continue
        params = [a.strip() for a in args.split(",") if a.strip()]
        sink = None; sig = []; call = []
        for p in params:
            n, t = [x.strip() for x in p.split(":", 1)]
            if t.startswith("StreamSink"):
                sink = n; sig.append(f"{n}: Arc<dyn EventSink>"); call.append(f"StreamSink::new({n})")
            elif t == "usize":
                sig.append(f"{n}: u32"); call.append(f"{n} as usize")
            else:
                sig.append(f"{n}: {t}"); call.append(n)
        res = ret.startswith("Result<")
        inner = ret[7:-1] if res else ret
        rty = (f"Result<{inner or '()'}, QiqError>" if res else (inner or "()"))
        target = f"api::{mod}::{name}({', '.join(call)})"
        attr = "#[uniffi::export]"
        if is_async:
            body = f"on_rt(async move {{ {target}.await }}).await" if res else f"on_rt_plain(async move {{ {target}.await }}).await"
            if not res: rty = f"Result<{inner or '()'}, QiqError>"
            out += [attr, f"pub async fn {name}({', '.join(sig)}) -> {rty} {{ {body} }}", ""]
        else:
            body = f"{target}.map_err(Into::into)" if res else target
            out += [attr, f"pub fn {name}({', '.join(sig)}) -> {rty} {{ {body} }}", ""]
open(os.path.join(root, "src/ffi.rs"), "w").write("\n".join(out))
