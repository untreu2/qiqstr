use std::sync::Arc;

#[uniffi::export(with_foreign)]
pub trait EventSink: Send + Sync {
    fn on_item(&self, item: String) -> bool;
    fn on_error(&self, message: String);
    fn on_done(&self);
    fn is_closed(&self) -> bool;
}

pub struct ForeignSink(pub Arc<dyn EventSink>);

impl qiqstr::sink::EventSink for ForeignSink {
    fn on_item(&self, item: String) -> bool {
        self.0.on_item(item)
    }

    fn on_error(&self, message: String) {
        self.0.on_error(message)
    }

    fn on_done(&self) {
        self.0.on_done()
    }

    fn is_closed(&self) -> bool {
        self.0.is_closed()
    }
}
