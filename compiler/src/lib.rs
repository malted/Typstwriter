mod world;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::PathBuf;
use std::sync::OnceLock;

use parking_lot::RwLock;
use typst::layout::PagedDocument;
use typst::syntax::{FileId, LinkedNode, VirtualPath, highlight, parse};

use crate::world::SystemWorld;

static WORLD: OnceLock<RwLock<SystemWorld>> = OnceLock::new();

fn world() -> &'static RwLock<SystemWorld> {
    WORLD.get_or_init(|| RwLock::new(SystemWorld::new(PathBuf::from("/"))))
}

#[repr(C)]
pub struct Buffer {
    data: *mut u8,
    len: usize,
}

#[repr(C)]
pub struct CompileResult {
    pdf: Buffer,
    error: *mut c_char,
}

/// Raster render result. `pixels` is premultiplied RGBA8, `width * height * 4`
/// bytes. `pages` is the total page count of the document (so the caller can
/// iterate). On error `pixels` is empty and `error` is non-null.
#[repr(C)]
pub struct RenderResult {
    pixels: Buffer,
    width: u32,
    height: u32,
    pages: u32,
    error: *mut c_char,
}

/// One page's pixels in a multi-page render.
#[repr(C)]
pub struct PageRender {
    pixels: Buffer,
    width: u32,
    height: u32,
}

/// Multi-page raster render result. `pages` points to `page_count` `PageRender`
/// entries. Free with `tw_free_render_all`.
#[repr(C)]
pub struct RenderAllResult {
    pages: *mut PageRender,
    page_count: usize,
    error: *mut c_char,
}

fn empty_render_all() -> RenderAllResult {
    RenderAllResult {
        pages: std::ptr::null_mut(),
        page_count: 0,
        error: std::ptr::null_mut(),
    }
}

fn empty_render() -> RenderResult {
    RenderResult {
        pixels: empty_buffer(),
        width: 0,
        height: 0,
        pages: 0,
        error: std::ptr::null_mut(),
    }
}

unsafe fn c_str_owned(p: *const c_char) -> String {
    if p.is_null() {
        return String::new();
    }
    unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned()
}

fn file_id_for(abs_path: &str) -> FileId {
    FileId::new(None, VirtualPath::new(abs_path))
}

fn into_buffer(data: Vec<u8>) -> Buffer {
    let mut boxed = data.into_boxed_slice();
    let buf = Buffer {
        data: boxed.as_mut_ptr(),
        len: boxed.len(),
    };
    std::mem::forget(boxed);
    buf
}

fn empty_buffer() -> Buffer {
    Buffer {
        data: std::ptr::null_mut(),
        len: 0,
    }
}

fn into_err(s: String) -> *mut c_char {
    CString::new(s).unwrap_or_default().into_raw()
}

/// Optional explicit init — also called lazily on first source/compile.
#[unsafe(no_mangle)]
pub extern "C" fn tw_init() {
    let _ = world();
}

/// Insert or update the in-memory source for a file.
#[unsafe(no_mangle)]
pub extern "C" fn tw_set_source(abs_path: *const c_char, text: *const c_char) {
    let path = unsafe { c_str_owned(abs_path) };
    let text = unsafe { c_str_owned(text) };
    let id = file_id_for(&path);
    world().read().set_source(id, text);
}

/// Compile `abs_main_path` to PDF. Returns a CompileResult; on failure `pdf`
/// is empty and `error` is a non-null C string (caller must free with
/// `tw_free_string`). On success `error` is null and caller frees `pdf` with
/// `tw_free_buf`.
#[unsafe(no_mangle)]
pub extern "C" fn tw_compile_pdf(abs_main_path: *const c_char) -> CompileResult {
    let path = unsafe { c_str_owned(abs_main_path) };
    let id = file_id_for(&path);

    let w_lock = world();
    {
        let mut w = w_lock.write();
        w.reset_dates();
        w.set_main(id);
    }

    let result = {
        let w = w_lock.read();
        typst::compile::<PagedDocument>(&*w)
    };

    comemo::evict(10);

    let doc = match result.output {
        Ok(d) => d,
        Err(errs) => {
            let msg = errs
                .iter()
                .map(|e| e.message.to_string())
                .collect::<Vec<_>>()
                .join("\n");
            return CompileResult {
                pdf: empty_buffer(),
                error: into_err(msg),
            };
        }
    };

    let pdf = match typst_pdf::pdf(&doc, &Default::default()) {
        Ok(p) => p,
        Err(errs) => {
            let msg = errs
                .iter()
                .map(|e| e.message.to_string())
                .collect::<Vec<_>>()
                .join("\n");
            return CompileResult {
                pdf: empty_buffer(),
                error: into_err(msg),
            };
        }
    };

    CompileResult {
        pdf: into_buffer(pdf),
        error: std::ptr::null_mut(),
    }
}

/// Compile + raster-render a single page at `pixel_per_pt` (e.g. 2.0 for
/// retina-ish). Returns premultiplied RGBA8 ready to wrap in a CGImage with
/// `kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big`.
#[unsafe(no_mangle)]
pub extern "C" fn tw_render_page(
    abs_main_path: *const c_char,
    page_index: u32,
    pixel_per_pt: f32,
) -> RenderResult {
    let path = unsafe { c_str_owned(abs_main_path) };
    let id = file_id_for(&path);

    let w_lock = world();
    {
        let mut w = w_lock.write();
        w.reset_dates();
        w.set_main(id);
    }

    let result = {
        let w = w_lock.read();
        typst::compile::<PagedDocument>(&*w)
    };

    comemo::evict(10);

    let doc = match result.output {
        Ok(d) => d,
        Err(errs) => {
            let msg = errs
                .iter()
                .map(|e| e.message.to_string())
                .collect::<Vec<_>>()
                .join("\n");
            let mut r = empty_render();
            r.error = into_err(msg);
            return r;
        }
    };

    let pages = doc.pages.len() as u32;
    let Some(page) = doc.pages.get(page_index as usize) else {
        let mut r = empty_render();
        r.pages = pages;
        r.error = into_err(format!("page index {page_index} out of range ({pages})"));
        return r;
    };

    let pixmap = typst_render::render(page, pixel_per_pt);
    let width = pixmap.width();
    let height = pixmap.height();
    let pixels = pixmap.take();

    RenderResult {
        pixels: into_buffer(pixels),
        width,
        height,
        pages,
        error: std::ptr::null_mut(),
    }
}

/// Compile + render every page individually. Returns a heap-allocated array of
/// `PageRender`; free with `tw_free_render_all`.
#[unsafe(no_mangle)]
pub extern "C" fn tw_render_all_pages(
    abs_main_path: *const c_char,
    pixel_per_pt: f32,
) -> RenderAllResult {
    let path = unsafe { c_str_owned(abs_main_path) };
    let id = file_id_for(&path);

    let w_lock = world();
    {
        let mut w = w_lock.write();
        w.reset_dates();
        w.set_main(id);
    }

    {
        let w = w_lock.read();
        match typst::World::source(&*w, id) {
            Ok(src) => eprintln!("=== template ({}) ===\n{}", path, src.text()),
            Err(e) => eprintln!("template fetch failed: {e}"),
        }
    }

    let result = {
        let w = w_lock.read();
        typst::compile::<PagedDocument>(&*w)
    };

    comemo::evict(10);

    let doc = match result.output {
        Ok(d) => d,
        Err(errs) => {
            let msg = errs
                .iter()
                .map(|e| e.message.to_string())
                .collect::<Vec<_>>()
                .join("\n");
            let mut r = empty_render_all();
            r.error = into_err(msg);
            return r;
        }
    };

    let pages: Vec<PageRender> = doc
        .pages
        .iter()
        .map(|p| {
            let pm = typst_render::render(p, pixel_per_pt);
            let width = pm.width();
            let height = pm.height();
            PageRender {
                pixels: into_buffer(pm.take()),
                width,
                height,
            }
        })
        .collect();

    let mut boxed = pages.into_boxed_slice();
    let page_count = boxed.len();
    let ptr = boxed.as_mut_ptr();
    std::mem::forget(boxed);

    RenderAllResult {
        pages: ptr,
        page_count,
        error: std::ptr::null_mut(),
    }
}

/// Compile + render the whole document as a single tall image (pages stacked
/// vertically with `gap_pt` points of whitespace between them). Background is
/// white.
#[unsafe(no_mangle)]
pub extern "C" fn tw_render_merged(
    abs_main_path: *const c_char,
    pixel_per_pt: f32,
    gap_pt: f32,
) -> RenderResult {
    use typst::layout::Abs;
    use typst::visualize::Color;

    let path = unsafe { c_str_owned(abs_main_path) };
    let id = file_id_for(&path);

    let w_lock = world();
    {
        let mut w = w_lock.write();
        w.reset_dates();
        w.set_main(id);
    }

    let result = {
        let w = w_lock.read();
        typst::compile::<PagedDocument>(&*w)
    };

    comemo::evict(10);

    let doc = match result.output {
        Ok(d) => d,
        Err(errs) => {
            let msg = errs
                .iter()
                .map(|e| e.message.to_string())
                .collect::<Vec<_>>()
                .join("\n");
            let mut r = empty_render();
            r.error = into_err(msg);
            return r;
        }
    };

    let pixmap = typst_render::render_merged(
        &doc,
        pixel_per_pt,
        Abs::pt(gap_pt as f64),
        Some(Color::WHITE),
    );
    let width = pixmap.width();
    let height = pixmap.height();
    let pages = doc.pages.len() as u32;

    RenderResult {
        pixels: into_buffer(pixmap.take()),
        width,
        height,
        pages,
        error: std::ptr::null_mut(),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn tw_free_render_all(result: RenderAllResult) {
    if !result.error.is_null() {
        unsafe { drop(CString::from_raw(result.error)) };
    }
    if result.pages.is_null() || result.page_count == 0 {
        return;
    }
    unsafe {
        let slice = std::slice::from_raw_parts_mut(result.pages, result.page_count);
        for p in slice.iter_mut() {
            if !p.pixels.data.is_null() && p.pixels.len > 0 {
                drop(Vec::from_raw_parts(
                    p.pixels.data,
                    p.pixels.len,
                    p.pixels.len,
                ));
            }
        }
        drop(Box::from_raw(std::slice::from_raw_parts_mut(
            result.pages,
            result.page_count,
        )));
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn tw_free_buf(buf: Buffer) {
    if buf.data.is_null() || buf.len == 0 {
        return;
    }
    unsafe {
        drop(Vec::from_raw_parts(buf.data, buf.len, buf.len));
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn tw_free_string(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    unsafe {
        drop(CString::from_raw(s));
    }
}

/// One highlighted span. `start`/`len` are **byte offsets** into the UTF-8
/// source. `kind` is a `TwHighlightKind`.
#[repr(C)]
pub struct HighlightRun {
    start: u32,
    len: u32,
    kind: u8,
    _pad: [u8; 3],
}

#[repr(C)]
pub struct HighlightResult {
    runs: *mut HighlightRun,
    count: usize,
}

/// Highlight tag codes. Stable order — append new variants at the end.
#[repr(u8)]
pub enum TwHighlightKind {
    Comment = 0,
    Punctuation = 1,
    Escape = 2,
    Strong = 3,
    Emph = 4,
    Link = 5,
    Raw = 6,
    Label = 7,
    Ref = 8,
    Heading = 9,
    ListMarker = 10,
    ListTerm = 11,
    MathDelimiter = 12,
    MathOperator = 13,
    Keyword = 14,
    Operator = 15,
    Number = 16,
    String = 17,
    Function = 18,
    Interpolated = 19,
    Error = 20,
}

fn tag_kind(tag: typst::syntax::Tag) -> u8 {
    use typst::syntax::Tag::*;
    match tag {
        Comment => 0,
        Punctuation => 1,
        Escape => 2,
        Strong => 3,
        Emph => 4,
        Link => 5,
        Raw => 6,
        Label => 7,
        Ref => 8,
        Heading => 9,
        ListMarker => 10,
        ListTerm => 11,
        MathDelimiter => 12,
        MathOperator => 13,
        Keyword => 14,
        Operator => 15,
        Number => 16,
        String => 17,
        Function => 18,
        Interpolated => 19,
        Error => 20,
    }
}

fn collect_highlights(node: &LinkedNode, out: &mut Vec<HighlightRun>) {
    if let Some(tag) = highlight(node) {
        let r = node.range();
        out.push(HighlightRun {
            start: r.start as u32,
            len: (r.end - r.start) as u32,
            kind: tag_kind(tag),
            _pad: [0; 3],
        });
    }
    for child in node.children() {
        collect_highlights(&child, out);
    }
}

/// Parse `text` and return highlight runs. Spans may overlap (e.g. `Strong`
/// inside `Heading`); apply them outer-first so inner ranges win. Free with
/// `tw_free_highlight`.
#[unsafe(no_mangle)]
pub extern "C" fn tw_highlight(text: *const c_char) -> HighlightResult {
    let s = unsafe { c_str_owned(text) };
    let root = parse(&s);
    let mut runs = Vec::new();
    collect_highlights(&LinkedNode::new(&root), &mut runs);

    let mut boxed = runs.into_boxed_slice();
    let count = boxed.len();
    let ptr = boxed.as_mut_ptr();
    std::mem::forget(boxed);

    HighlightResult { runs: ptr, count }
}

#[unsafe(no_mangle)]
pub extern "C" fn tw_free_highlight(result: HighlightResult) {
    if result.runs.is_null() || result.count == 0 {
        return;
    }
    unsafe {
        drop(Box::from_raw(std::slice::from_raw_parts_mut(
            result.runs,
            result.count,
        )));
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn add(left: u64, right: u64) -> u64 {
    left + right
}
