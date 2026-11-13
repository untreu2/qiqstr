use std::marker::PhantomData;
use std::sync::Arc;

#[uniffi::export(with_foreign)]
pub trait EventSink: Send + Sync {
    fn on_item(&self, item: String) -> bool;
    fn on_error(&self, message: String);
    fn on_done(&self);
    fn is_closed(&self) -> bool;
}

pub struct SinkClosed;

pub struct StreamSink<T> {
    inner: Arc<dyn EventSink>,
    _marker: PhantomData<T>,
}

impl<T> Clone for StreamSink<T> {
    fn clone(&self) -> Self {
        Self { inner: self.inner.clone(), _marker: PhantomData }
    }
}

impl StreamSink<String> {
    pub fn new(inner: Arc<dyn EventSink>) -> Self {
        Self { inner, _marker: PhantomData }
    }

    pub fn add(&self, item: String) -> Result<(), SinkClosed> {
        if self.inner.on_item(item) { Ok(()) } else { Err(SinkClosed) }
    }

    pub fn add_error<E: std::fmt::Display>(&self, error: E) -> Result<(), SinkClosed> {
        self.inner.on_error(error.to_string());
        Ok(())
    }

    pub fn is_closed(&self) -> bool {
        self.inner.is_closed()
    }

    pub fn done(&self) {
        self.inner.on_done();
    }
}
