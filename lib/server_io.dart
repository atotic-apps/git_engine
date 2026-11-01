/// The `dart:io` adapter of the smart HTTP processing.
///
/// Import this library in a host that serves repositories over `dart:io`,
/// together with the server contracts of `git_engine.dart`.
library;

export 'src/server/dart_io/dart_io_body_decoder.dart'
    show dartIoGzipBodyDecoder;
export 'src/server/dart_io/dart_io_git_http_server.dart'
    show DartIoGitHttpServer;
