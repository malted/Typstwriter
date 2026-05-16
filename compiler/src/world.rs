use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::OnceLock;

use chrono::{DateTime, Datelike, Local};
use parking_lot::Mutex;
use typst::diag::{FileError, FileResult, PackageError, PackageResult};
use typst::foundations::{Bytes, Datetime};
use typst::syntax::package::PackageSpec;
use typst::syntax::{FileId, Source, VirtualPath};
use typst::text::{Font, FontBook};
use typst::utils::LazyHash;
use typst::{Library, LibraryExt, World};

use typst_kit::download::{Downloader, ProgressSink};
use typst_kit::fonts::{FontSearcher, FontSlot};
use typst_kit::package::PackageStorage;

pub struct SystemWorld {
    root: PathBuf,
    main: FileId,
    library: LazyHash<Library>,
    book: LazyHash<FontBook>,
    fonts: Vec<FontSlot>,
    packages: PackageStorage,
    slots: Mutex<HashMap<FileId, FileSlot>>,
    now: OnceLock<DateTime<Local>>,
}

struct FileSlot {
    source: Option<Source>,
    bytes: Option<Bytes>,
}

impl SystemWorld {
    pub fn new(root: PathBuf) -> Self {
        let mut searcher = FontSearcher::new();
        searcher.include_system_fonts(true).include_embedded_fonts(true);
        let fonts = searcher.search();

        let packages = PackageStorage::new(
            None,
            None,
            Downloader::new(concat!("typstwriter/", env!("CARGO_PKG_VERSION"))),
        );

        let placeholder = FileId::new(None, VirtualPath::new("__placeholder__.typ"));

        Self {
            root,
            main: placeholder,
            library: LazyHash::new(Library::builder().build()),
            book: LazyHash::new(fonts.book),
            fonts: fonts.fonts,
            packages,
            slots: Mutex::new(HashMap::new()),
            now: OnceLock::new(),
        }
    }

    pub fn set_root(&mut self, root: PathBuf) {
        if root != self.root {
            self.root = root;
            // Reset comemo since paths underneath change semantics.
            comemo::evict(0);
        }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn set_main(&mut self, id: FileId) {
        self.main = id;
    }

    /// Insert or replace a source buffer. Uses incremental reparse when possible.
    pub fn set_source(&self, id: FileId, text: String) {
        let mut slots = self.slots.lock();
        let slot = slots.entry(id).or_insert(FileSlot { source: None, bytes: None });
        match &mut slot.source {
            Some(src) if src.text() != text => {
                src.replace(&text);
            }
            Some(_) => {} // unchanged
            None => slot.source = Some(Source::new(id, text)),
        }
    }

    pub fn reset_dates(&mut self) {
        self.now = OnceLock::new();
    }

    /// Resolve a FileId to an on-disk path, fetching its package if needed.
    fn system_path(&self, id: FileId) -> FileResult<PathBuf> {
        let vpath = id.vpath();
        if let Some(spec) = id.package() {
            let pkg_root = self.prepare_package(spec).map_err(FileError::Package)?;
            vpath
                .resolve(&pkg_root)
                .ok_or(FileError::AccessDenied)
        } else {
            vpath
                .resolve(&self.root)
                .ok_or(FileError::AccessDenied)
        }
    }

    fn prepare_package(&self, spec: &PackageSpec) -> PackageResult<PathBuf> {
        self.packages.prepare_package(spec, &mut ProgressSink)
    }

    fn read_bytes(&self, id: FileId) -> FileResult<Bytes> {
        let path = self.system_path(id)?;
        std::fs::read(&path)
            .map(Bytes::new)
            .map_err(|e| FileError::from_io(e, &path))
    }

    fn read_source(&self, id: FileId) -> FileResult<Source> {
        let path = self.system_path(id)?;
        let text = std::fs::read_to_string(&path)
            .map_err(|e| FileError::from_io(e, &path))?;
        Ok(Source::new(id, text))
    }
}

impl World for SystemWorld {
    fn library(&self) -> &LazyHash<Library> {
        &self.library
    }

    fn book(&self) -> &LazyHash<FontBook> {
        &self.book
    }

    fn main(&self) -> FileId {
        self.main
    }

    fn source(&self, id: FileId) -> FileResult<Source> {
        let mut slots = self.slots.lock();
        let slot = slots.entry(id).or_insert(FileSlot { source: None, bytes: None });
        if let Some(src) = &slot.source {
            return Ok(src.clone());
        }
        let src = self.read_source(id)?;
        slot.source = Some(src.clone());
        Ok(src)
    }

    fn file(&self, id: FileId) -> FileResult<Bytes> {
        let mut slots = self.slots.lock();
        let slot = slots.entry(id).or_insert(FileSlot { source: None, bytes: None });
        if let Some(b) = &slot.bytes {
            return Ok(b.clone());
        }
        let b = self.read_bytes(id)?;
        slot.bytes = Some(b.clone());
        Ok(b)
    }

    fn font(&self, index: usize) -> Option<Font> {
        self.fonts.get(index)?.get()
    }

    fn today(&self, offset: Option<i64>) -> Option<Datetime> {
        let now = self.now.get_or_init(Local::now);
        let naive = match offset {
            None => now.naive_local(),
            Some(h) => now.naive_utc() + chrono::Duration::hours(h),
        };
        Datetime::from_ymd(naive.year(), naive.month() as u8, naive.day() as u8)
    }
}

