add_swift_library(swiftFrontend STATIC
  ArgsToFrontendInputsConverter.cpp
  ArgsToFrontendOptionsConverter.cpp
  CompilerInvocation.cpp
  DiagnosticVerifier.cpp
  Frontend.cpp
  FrontendInputs.cpp
  FrontendOptions.cpp
  PrintingDiagnosticConsumer.cpp
  SerializedDiagnosticConsumer.cpp
  DEPENDS
    SwiftOptions
  LINK_LIBRARIES
    swiftSIL
    swiftMigrator
    swiftOption
    swiftParseSIL
    swiftSema
    swiftSerialization)

