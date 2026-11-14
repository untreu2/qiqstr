use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;

use crate::frb_generated::StreamSink;

struct DartSink {
    sink: StreamSink<String>,
    closed: AtomicBool,
}

impl qiqstr::sink::EventSink for DartSink {
    fn on_item(&self, item: String) -> bool {
        let delivered = self.sink.add(item).is_ok();
        if !delivered {
            self.closed.store(true, Ordering::Relaxed);
        }
        delivered
    }

    fn on_error(&self, message: String) {
        if self.sink.add_error(anyhow::anyhow!(message)).is_err() {
            self.closed.store(true, Ordering::Relaxed);
        }
    }

    fn on_done(&self) {}

    fn is_closed(&self) -> bool {
        self.closed.load(Ordering::Relaxed)
    }
}

pub(crate) fn dart_sink(sink: StreamSink<String>) -> qiqstr::sink::StreamSink<String> {
    qiqstr::sink::StreamSink::new(Arc::new(DartSink {
        sink,
        closed: AtomicBool::new(false),
    }))
}
