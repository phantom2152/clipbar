# ClipBar

ClipBar is a lightweight clipboard manager for macOS. It lives in the menu bar and keeps a searchable history of copied text and images, with support for pinned clips and image previews.

## Requirements

- macOS 13 or later
- Swift 6 and the Xcode Command Line Tools

## Build and run

From the project directory, run:

```sh
./build.sh
```

This builds `ClipBar.app` and launches it. Click the menu-bar icon to open the clipboard; right-click it to quit.

To build without launching the app:

```sh
swift build -c release
```

Clipboard data is stored in `~/Library/Application Support/ClipBar`.

## License

ClipBar is available under the [MIT License](LICENSE).
