# A connector to enable macos media control for ncspot

This small menu bar app runs in the background while listening to events from the ncspot socket and updating its now playing status.

When macos media control events are received, it sends the appropriate command to the same ncspot unix socket.

This allows integration with airpods ear detection, automatic device switching, etc.
