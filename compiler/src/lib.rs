use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use typst::foundations::{Dict, IntoValue};
use typst_as_lib::TypstEngine;
use typst_as_lib::typst_kit_options::TypstKitFontOptions;

#[unsafe(no_mangle)]
pub extern "C" fn openwater_init() -> *const c_char {
    let message = "Hello Diego from Rust!";
    let c_str = CString::new(message).unwrap();
    c_str.into_raw() as *const c_char
}

#[unsafe(no_mangle)]
pub extern "C" fn add(left: u64, right: u64) -> u64 {
    left + right
}

#[unsafe(no_mangle)]
#[repr(C)]
pub struct Buffer {
    data: *mut u8,
    len: usize,
}

#[unsafe(no_mangle)]
pub extern "C" fn compile_typst(typst_template_string: *const std::ffi::c_char) -> Buffer {
    eprintln!("Compiling!");

    let source = unsafe { CStr::from_ptr(typst_template_string) }
        .to_string_lossy()
        .into_owned();

    eprintln!("Source: {source}");

    let template = TypstEngine::builder()
        .main_file(source)
        // .fonts(FONTS.iter().copied())
        .search_fonts_with(TypstKitFontOptions::default())
        .with_package_file_resolver()
        .build();

    // let mut inputs = Dict::new();
    // inputs.insert("email".into(), email.into_value());

    // let compilation_result = template.compile_with_input(inputs);
    let compilation_result = template.compile();

    for warning in &compilation_result.warnings {
        eprintln!("Typst warning: {:?}", warning);
    }

    let document = compilation_result
        .output
        .expect("typst::compile() returned an error!");

    let options = Default::default();
    let pdf = typst_pdf::pdf(&document, &options).expect("Could not generate pdf.");

    let mut buf = pdf.into_boxed_slice();
    let data = buf.as_mut_ptr();
    let len = buf.len();
    std::mem::forget(buf);
    Buffer { data, len }
}

#[unsafe(no_mangle)]
pub extern "C" fn free_buf(buf: Buffer) {
    let s = unsafe { std::slice::from_raw_parts_mut(buf.data, buf.len) };
    let s = s.as_mut_ptr();
    drop(unsafe { Box::from_raw(s) })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn it_works() {
        let result = add(2, 2);
        assert_eq!(result, 4);
    }
}
