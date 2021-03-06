//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2018 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftShims

//
// Largely inspired by string-recore at
// https://github.com/apple/swift/pull/10747.
//

//
// StringGuts is always 16 bytes on both 32bit and 64bit platforms. This
// effectively makes the worse-case (from a spare bit perspective) ABIs be the
// 64bit ones, as all 32bit pointers effectively have a 32-bit address space
// while the 64bit ones have a 56-bit address space.
//
// Of the 64bit ABIs, x86_64 has the fewest spare bits, so that's the ABI we
// design for.
//
// FIXME: what about ppc64 and s390x?
//

@_fixed_layout
public // FIXME
struct _StringGuts {
  public // FIXME for testing only
  var _object: _StringObject

  public // FIXME for testing only
  var _otherBits: UInt // (Mostly) count or inline storage

  @_inlineable
  @inline(__always)
  public
  init(object: _StringObject, otherBits: UInt) {
    self._object = object
    self._otherBits = otherBits
    _invariantCheck()
  }

  public typealias _RawBitPattern = (_StringObject._RawBitPattern, UInt)

  @_versioned
  @_inlineable
  internal var rawBits: _RawBitPattern {
    @inline(__always)
    get {
      return (_object.rawBits, _otherBits)
    }
  }

  init(rawBits: _RawBitPattern) {
    self.init(
      object: _StringObject(rawBits: rawBits.0),
      otherBits: rawBits.1)
  }
}

extension _StringGuts {
  @_inlineable // FIXME(sil-serialize-all)
  @_versioned // FIXME(sil-serialize-all)
  internal func _invariantCheck() {
#if INTERNAL_CHECKS_ENABLED
    _object._invariantCheck()
    if _object.isNative {
      _sanityCheck(UInt(_object.nativeRawStorage.count) == self._otherBits)
    } else if _object.isUnmanaged {
    } else if _object.isCocoa {
      if _object.isContiguous {
        _sanityCheck(_isValidAddress(_otherBits))
      } else {
        _sanityCheck(_otherBits == 0)
      }
    } else if _object.isSmall {
    } else {
      fatalError("Unimplemented string form")
    }

#if arch(i386) || arch(arm)
  _sanityCheck(MemoryLayout<String>.size == 12, """
    the runtime is depending on this, update Reflection.mm and \
    this if you change it
    """)
#else
  _sanityCheck(MemoryLayout<String>.size == 16, """
    the runtime is depending on this, update Reflection.mm and \
    this if you change it
    """)
#endif

#endif // INTERNAL_CHECKS_ENABLED
  }

  @_inlineable
  @inline(__always)
  public // @testable
  mutating func isUniqueNative() -> Bool {
    guard _isNative else { return false }
    // Note that the isUnique test must be in a separate statement;
    // `isNative && _isUnique` always evaluates to false in debug builds,
    // because SILGen keeps the self reference in `isNative` alive for the
    // duration of the expression.

    // Note that we have to perform this operation here, and not as a (even
    // mutating) method on our _StringObject to avoid all chances of a semantic
    // copy.
    //
    // FIXME: Super hacky. Is there a better way?
    defer { _fixLifetime(self) }
    var bitPattern = _object.referenceBits
    return _isUnique_native(&bitPattern)
  }
}

extension _StringGuts {
  @_inlineable
  public // @testable
  var isASCII: Bool {
    // FIXME: Currently used to sometimes mean contiguous ASCII
    return _object.isContiguousASCII
  }

  @_inlineable
  public // @testable
  var _isNative: Bool {
    return _object.isNative
  }

#if _runtime(_ObjC)
  @_inlineable
  public // @testable
  var _isCocoa: Bool {
    return _object.isCocoa
  }
#endif

  @_inlineable
  public // @testable
  var _isUnmanaged: Bool {
    return _object.isUnmanaged
  }

  @_inlineable
  public // @testable
  var _isSmall: Bool {
    return _object.isSmall
  }

  @_inlineable
  public // @testable
  var _owner: AnyObject? {
    return _object.owner
  }

  @_inlineable
  public // @testable
  var isSingleByte: Bool {
    // FIXME: Currently used to sometimes mean contiguous ASCII
    return _object.isSingleByte
  }

  @_versioned
  @_inlineable
  internal
  var _isEmptySingleton: Bool {
    return _object.isEmptySingleton
  }

  @_inlineable
  public // @testable
  var byteWidth: Int {
    return _object.byteWidth
  }

  @_versioned
  @_inlineable
  internal
  var _nativeCount: Int {
    @inline(__always) get {
      _sanityCheck(_object.isNative)
      return Int(bitPattern: _otherBits)
    }
    @inline(__always) set {
      _sanityCheck(_object.isNative)
      _sanityCheck(newValue >= 0)
      _otherBits = UInt(bitPattern: newValue)
    }
  }

  @_versioned
  @inline(__always)
  internal
  init<CodeUnit>(_ storage: _SwiftStringStorage<CodeUnit>)
  where CodeUnit : FixedWidthInteger & UnsignedInteger {
    _sanityCheck(storage.count >= 0)
    self.init(
      object: _StringObject(storage),
      otherBits: UInt(bitPattern: storage.count))
  }
}

extension _StringGuts {
  @_inlineable
  @inline(__always)
  public // @testable
  init() {
    self.init(object: _StringObject(), otherBits: 0)
    _invariantCheck()
  }
}

#if _runtime(_ObjC)
extension _StringGuts {
  //
  // FIXME(TODO: JIRA): HACK HACK HACK: Work around for ARC :-(
  //
  @_versioned
  @effects(readonly)
  internal static func getCocoaLength(_unsafeBitPattern: UInt) -> Int {
    return _stdlib_binary_CFStringGetLength(
      Builtin.reinterpretCast(_unsafeBitPattern))
  }

  @_versioned
  @_inlineable
  var _cocoaCount: Int {
    @inline(__always)
    get {
      _sanityCheck(_object.isCocoa)
      defer { _fixLifetime(self) }
      return _StringGuts.getCocoaLength(
        _unsafeBitPattern: _object.referenceBits)
      // _stdlib_binary_CFStringGetLength(_object.asCocoaObject)
    }
  }

  @_versioned
  @_inlineable
  var _cocoaRawStart: UnsafeRawPointer {
    @inline(__always)
    get {
      _sanityCheck(_object.isContiguousCocoa)
      _sanityCheck(_isValidAddress(_otherBits))
      return UnsafeRawPointer(
        bitPattern: _otherBits
      )._unsafelyUnwrappedUnchecked
    }
  }

  @_versioned
  @_inlineable
  func _asContiguousCocoa<CodeUnit>(
    of codeUnit: CodeUnit.Type = CodeUnit.self
  ) -> _UnmanagedString<CodeUnit>
  where CodeUnit : FixedWidthInteger & UnsignedInteger {
    _sanityCheck(_object.isContiguousCocoa)
    _sanityCheck(CodeUnit.bitWidth == _object.bitWidth)
    let start = _cocoaRawStart.assumingMemoryBound(to: CodeUnit.self)
    return _UnmanagedString(start: start, count: _cocoaCount)
  }

  @_versioned
  internal
  init(
    _nonTaggedCocoaObject s: _CocoaString,
    count: Int,
    isSingleByte: Bool,
    start: UnsafeRawPointer?
  ) {
    _sanityCheck(!_isObjCTaggedPointer(s))
    guard count > 0 else {
      self.init()
      return
    }
    self.init(
      object: _StringObject(
        cocoaObject: s,
        isSingleByte: isSingleByte,
        isContiguous: start != nil),
      otherBits: UInt(bitPattern: start))
    if start == nil {
      _sanityCheck(_object.isOpaque)
    } else {
      _sanityCheck(_object.isContiguous)
    }
  }
}
#else // !_runtime(_ObjC)
extension _StringGuts {
  @_versioned
  @_inlineable
  internal
  var _opaqueCount: Int {
    @inline(__always) get {
      _sanityCheck(_object.isOpaque)
      return Int(bitPattern: _otherBits)
    }
  }

  @inline(never)
  @_versioned
  internal
  init<S: _OpaqueString>(opaqueString: S) {
    self.init(
      object: _StringObject(opaqueString: opaqueString),
      otherBits: UInt(bitPattern: opaqueString.length))
  }
}
#endif // _runtime(_ObjC)

extension _StringGuts {
  @_versioned
  @_inlineable
  internal var _unmanagedRawStart: UnsafeRawPointer {
    @inline(__always) get {
      _sanityCheck(_object.isUnmanaged)
      return _object.asUnmanagedRawStart
    }
  }

  @_versioned
  @_inlineable
  internal var _unmanagedCount: Int {
    @inline(__always) get {
      _sanityCheck(_object.isUnmanaged)
      return Int(bitPattern: _otherBits)
    }
  }

  @_versioned
  @_inlineable
  @inline(__always)
  internal
  func _asUnmanaged<CodeUnit>(
    of codeUnit: CodeUnit.Type = CodeUnit.self
  ) -> _UnmanagedString<CodeUnit>
  where CodeUnit : FixedWidthInteger & UnsignedInteger {
    _sanityCheck(_object.isUnmanaged)
    _sanityCheck(CodeUnit.bitWidth == _object.bitWidth)
    let start = _unmanagedRawStart.assumingMemoryBound(to: CodeUnit.self)
    let count = _unmanagedCount
    _sanityCheck(count >= 0)
    return _UnmanagedString(start: start, count: count)
  }

  @_versioned
  @_inlineable
  init<CodeUnit>(_ s: _UnmanagedString<CodeUnit>)
  where CodeUnit : FixedWidthInteger & UnsignedInteger {
    _sanityCheck(s.count >= 0)
    self.init(
      object: _StringObject(unmanaged: s.start),
      otherBits: UInt(bitPattern: s.count))
    _sanityCheck(_object.isUnmanaged)
    _sanityCheck(_unmanagedRawStart == s.rawStart)
    _sanityCheck(_unmanagedCount == s.count)
    _invariantCheck()
  }
}

#if _runtime(_ObjC)
extension _StringGuts {
  //
  // NOTE: For now, small strings are tagged cocoa strings
  //
  @_versioned
  @_inlineable
  internal var _taggedCocoaCount: Int {
    @inline(__always) get {
#if arch(i386) || arch(arm)
      _sanityCheckFailure("Tagged Cocoa objects aren't supported on 32-bit platforms")
#else
      _sanityCheck(_object.isSmall)
      return Int(truncatingIfNeeded: _object.payloadBits)
#endif
    }
  }

  @_versioned
  @_inlineable
  internal var _taggedCocoaObject: _CocoaString {
    @inline(__always) get {
#if arch(i386) || arch(arm)
      _sanityCheckFailure("Tagged Cocoa objects aren't supported on 32-bit platforms")
#else
      _sanityCheck(_object.isSmall)
      return Builtin.reinterpretCast(_otherBits)
#endif
    }
  }

  @_versioned
  @inline(never) // Hide CF dependency
  internal init(_taggedCocoaObject object: _CocoaString) {
#if arch(i386) || arch(arm)
    _sanityCheckFailure("Tagged Cocoa objects aren't supported on 32-bit platforms")
#else
    _sanityCheck(_isObjCTaggedPointer(object))
    let count = _stdlib_binary_CFStringGetLength(object)
    self.init(
      object: _StringObject(
        smallStringPayload: UInt(count), isSingleByte: false),
      otherBits: Builtin.reinterpretCast(object))
    _sanityCheck(_object.isSmall)
#endif
  }
}
#endif // _runtime(_ObjC)

extension _StringGuts {
  @_versioned
  @_inlineable
  internal
  var _unmanagedASCIIView: _UnmanagedString<UInt8> {
    @effects(readonly)
    get {
      _sanityCheck(_object.isContiguousASCII)
      if _object.isUnmanaged {
        return _asUnmanaged()
      } else if _object.isNative {
        return _object.nativeStorage(of: UInt8.self).unmanagedView
      } else {
#if _runtime(_ObjC)
        _sanityCheck(_object.isContiguousCocoa)
        return _asContiguousCocoa(of: UInt8.self)
#else
        Builtin.unreachable()
#endif
      }
    }
  }

  @_versioned
  @_inlineable
  internal
  var _unmanagedUTF16View: _UnmanagedString<UTF16.CodeUnit> {
    @effects(readonly)
    get {
      _sanityCheck(_object.isContiguousUTF16)
      if _object.isUnmanaged {
        return _asUnmanaged()
      } else if _object.isNative {
        return _object.nativeStorage(of: UTF16.CodeUnit.self).unmanagedView
      } else {
#if _runtime(_ObjC)
        _sanityCheck(_object.isContiguousCocoa)
        return _asContiguousCocoa(of: UTF16.CodeUnit.self)
#else
        Builtin.unreachable()
#endif
      }
    }
  }
}

extension _StringGuts {
  @_versioned
  @_inlineable
  internal
  var _isOpaque: Bool {
    @inline(__always)
    get { return _object.isOpaque }
  }

  @_versioned
  @_inlineable
  internal
  var _isContiguous: Bool {
    @inline(__always)
    get { return _object.isContiguous }
  }
}

#if _runtime(_ObjC)
extension _StringGuts {
  /// Return an NSString instance containing a slice of this string.
  /// The returned object may contain unmanaged pointers into the
  /// storage of this string; you are responsible for ensuring that
  /// it will not outlive `self`.
  @_versioned
  @_inlineable
  internal
  func _ephemeralCocoaString() -> _CocoaString {
    if _object.isNative {
      return _object.asNativeObject
    }
    if _object.isCocoa {
      return _object.asCocoaObject
    }
    if _object.isSmall {
      return _taggedCocoaObject
    }
    _sanityCheck(_object.isUnmanaged)
    if _object.isSingleByte {
      return _NSContiguousString(_StringGuts(_asUnmanaged(of: UInt8.self)))
    }

    return _NSContiguousString(
      _StringGuts(_asUnmanaged(of: UTF16.CodeUnit.self)))
  }

  /// Return an NSString instance containing a slice of this string.
  /// The returned object may contain unmanaged pointers into the
  /// storage of this string; you are responsible for ensuring that
  /// it will not outlive `self`.
  @_versioned
  @_inlineable
  internal
  func _ephemeralCocoaString(_ range: Range<Int>) -> _CocoaString {
    if _slowPath(_isOpaque) {
      return _asOpaque()[range].cocoaSlice()
    }
    return _NSContiguousString(_unmanaged: self, range: range)
  }

  public // @testable
  var _underlyingCocoaString: _CocoaString? {
    if _object.isNative {
      return _object.nativeRawStorage
    }
    if _object.isCocoa {
      return _object.asCocoaObject
    }
    if _object.isSmall {
      return _taggedCocoaObject
    }
    return nil
  }
}
#endif

extension _StringGuts {
  /// Return the object identifier for the reference counted heap object
  /// referred to by this string (if any). This is useful for testing allocation
  /// behavior.
  public // @testable
  var _objectIdentifier: ObjectIdentifier? {
    if _object.isNative {
      return ObjectIdentifier(_object.nativeRawStorage)
    }
#if _runtime(_ObjC)
    if _object.isCocoa {
      return ObjectIdentifier(_object.asCocoaObject)
    }
#else
    if _object.isOpaque {
      return ObjectIdentifier(_object.asOpaqueObject)
    }
#endif
    return nil
  }
}

extension _StringGuts {
  @inline(never)
  @_versioned
  internal func _asOpaque() -> _UnmanagedOpaqueString {
#if _runtime(_ObjC)
    if _object.isSmall {
      return _UnmanagedOpaqueString(
        _taggedCocoaObject, count: _taggedCocoaCount)
    }
    _sanityCheck(_object.isNoncontiguousCocoa)
    return _UnmanagedOpaqueString(_object.asCocoaObject, count: _cocoaCount)
#else
    _sanityCheck(_object.isOpaque)
    return _UnmanagedOpaqueString(_object.asOpaqueObject, count: _opaqueCount)
#endif
  }
}

extension _StringGuts {
  // FIXME: Remove
  public func _dump() {
    func printHex(_ uint: UInt, newline: Bool = true) {
      print(String(uint, radix: 16), terminator: newline ? "\n" : "")
    }
    func fromAny(_ x: AnyObject) -> UInt {
      return Builtin.reinterpretCast(x)
    }
    func fromPtr(_ x: UnsafeMutableRawPointer) -> UInt {
      return Builtin.reinterpretCast(x)
    }

    print("_StringGuts(", terminator: "")
    printHex(UInt(rawBits.0), newline: false)
    print(" ", terminator: "")
    printHex(UInt(rawBits.1), newline: false)
    print(": ", terminator: "")
    if _object.isNative {
      let storage = _object.nativeRawStorage
      print("native ", terminator: "")
      printHex(Builtin.reinterpretCast(storage), newline: false)
      print(" start: ", terminator: "")
      printHex(Builtin.reinterpretCast(storage.rawStart), newline: false)
      print(" count: ", terminator: "")
      print(storage.count, terminator: "")
      print("/", terminator: "")
      print(storage.capacity, terminator: "")
      return
    }
#if _runtime(_ObjC)
    if _object.isCocoa {
      print("cocoa ", terminator: "")
      printHex(Builtin.reinterpretCast(_object.asCocoaObject), newline: false)
      print(" start: ", terminator: "")
      if _object.isContiguous {
        printHex(Builtin.reinterpretCast(_cocoaRawStart), newline: false)
      } else {
        print("<opaque>", terminator: "")
      }
      print(" count: ", terminator: "")
      print(_cocoaCount, terminator: "")
      return
    }
#else
    if _object.isOpaque {
      print("opaque ", terminator: "")
      printHex(Builtin.reinterpretCast(_object.asOpaqueObject), newline: false)
      print(" count: ", terminator: "")
      print(_opaqueCount, terminator: "")
      return
    }
#endif
    if _object.isUnmanaged {
      print("unmanaged ", terminator: "")
      printHex(Builtin.reinterpretCast(_unmanagedRawStart), newline: false)
      print(" count: ", terminator: "")
      print(_unmanagedCount, terminator: "")
      return
    }
#if _runtime(_ObjC)
    if _object.isSmall {
      print("small cocoa ", terminator: "")
      printHex(Builtin.reinterpretCast(_taggedCocoaObject), newline: false)
      print(" count: ", terminator: "")
      print(_taggedCocoaCount, terminator: "")
      return
    }
#endif
    print("error", terminator: "")
    if isASCII {
      print(" <ascii>", terminator: "")
    }
    else {
      print(" <utf16>", terminator: "")
    }
    print(")")
  }
}

//
// String API helpers
//
extension _StringGuts {
  // Return a contiguous _StringGuts with the same contents as this one.
  // Use the existing guts if possible; otherwise copy the string into a
  // new buffer.
  @_versioned
  internal
  func _extractContiguous<CodeUnit>(
    of codeUnit: CodeUnit.Type = CodeUnit.self
  ) -> _StringGuts
  where CodeUnit : FixedWidthInteger & UnsignedInteger {
    if _fastPath(
      _object.isContiguous && CodeUnit.bitWidth == _object.bitWidth) {
      return self
    }
    let count = self.count
    return _StringGuts(_copyToNativeStorage(of: CodeUnit.self, from: 0..<count))
  }

  @_versioned
  internal
  func _extractContiguousUTF16() -> _StringGuts {
    return _extractContiguous(of: UTF16.CodeUnit.self)
  }

  @_versioned
  internal
  func _extractContiguousASCII() -> _StringGuts {
    return _extractContiguous(of: UInt8.self)
  }

  // Return a native storage object with the same contents as this string.
  // Use the existing buffer if possible; otherwise copy the string into a
  // new buffer.
  @_versioned
  internal
  func _extractNativeStorage<CodeUnit>(
    of codeUnit: CodeUnit.Type = CodeUnit.self
  ) -> _SwiftStringStorage<CodeUnit>
  where CodeUnit : FixedWidthInteger & UnsignedInteger {
    if _fastPath(_object.isNative && CodeUnit.bitWidth == _object.bitWidth) {
      return _object.nativeStorage()
    }
    let count = self.count
    return _copyToNativeStorage(of: CodeUnit.self, from: 0..<count)
  }

  @_specialize(where CodeUnit == UInt8)
  @_specialize(where CodeUnit == UInt16)
  @_specialize(where CodeUnit == UTF16.CodeUnit)
  @_versioned
  @_inlineable
  internal
  func _copyToNativeStorage<CodeUnit>(
    of codeUnit: CodeUnit.Type = CodeUnit.self,
    from range: Range<Int>,
    unusedCapacity: Int = 0
  ) -> _SwiftStringStorage<CodeUnit>
  where CodeUnit : FixedWidthInteger & UnsignedInteger {
    _sanityCheck(unusedCapacity >= 0)
    let storage = _SwiftStringStorage<CodeUnit>.create(
      capacity: range.count + unusedCapacity,
      count: range.count)
    self._copy(range: range, into: storage.usedBuffer)
    return storage
  }

  @_inlineable
  public // @testable
  func _extractSlice(_ range: Range<Int>) -> _StringGuts {
    if range.isEmpty { return _StringGuts() }
    if range == 0..<count { return self }
    switch (isASCII, _object.isUnmanaged) {
    case (true, true):
        return _StringGuts(_asUnmanaged(of: UInt8.self)[range])
    case (true, false):
      return _StringGuts(_copyToNativeStorage(of: UInt8.self, from: range))
    case (false, true):
      return _StringGuts(_asUnmanaged(of: UTF16.CodeUnit.self)[range])
    case (false, false):
      return _StringGuts(
        _copyToNativeStorage(of: UTF16.CodeUnit.self, from: range))
    }
  }

  @_versioned
  @_inlineable
  internal mutating func allocationParametersForMutableStorage<CodeUnit>(
    of type: CodeUnit.Type,
    unusedCapacity: Int
  ) -> (count: Int, capacity: Int)?
  where CodeUnit : FixedWidthInteger & UnsignedInteger {
    if _slowPath(!_object.isNative) {
      return (self.count, count + unusedCapacity)
    }
    unowned(unsafe) let storage = _object.nativeRawStorage
    defer { _fixLifetime(self) }
    if _slowPath(storage.unusedCapacity < unusedCapacity) {
      // Need more space; borrow Array's exponential growth curve.
      return (
        storage.count,
        Swift.max(
          _growArrayCapacity(storage.capacity),
          count + unusedCapacity))
    }
    // We have enough space; check if it's unique and of the correct width.
    if _fastPath(_object.bitWidth == CodeUnit.bitWidth) {
      if _fastPath(isUniqueNative()) {
        return nil
      }
    }
    // If not, allocate new storage, but keep existing capacity.
    return (storage.count, storage.capacity)
  }

  // Convert ourselves (if needed) to a native string with the specified storage
  // parameters and call `body` on the resulting native storage.
  @_versioned
  @_inlineable
  internal
  mutating func withMutableStorage<CodeUnit, R>(
    of type: CodeUnit.Type = CodeUnit.self,
    unusedCapacity: Int,
    _ body: (Unmanaged<_SwiftStringStorage<CodeUnit>>) -> R
  ) -> R
  where CodeUnit : FixedWidthInteger & UnsignedInteger {
    let paramsOpt = allocationParametersForMutableStorage(
      of: CodeUnit.self,
      unusedCapacity: unusedCapacity)
    if _fastPath(paramsOpt == nil) {
      unowned(unsafe) let storage = _object.nativeStorage(of: CodeUnit.self)
      let result = body(Unmanaged.passUnretained(storage))
      self._nativeCount = storage.count
      _fixLifetime(self)
      return result
    }
    let params = paramsOpt._unsafelyUnwrappedUnchecked
    let unmanagedRef = Unmanaged.passRetained(
      self._copyToNativeStorage(
        of: CodeUnit.self,
        from: 0..<params.count,
        unusedCapacity: params.capacity - params.count))
    let result = body(unmanagedRef)
    self = _StringGuts(unmanagedRef.takeRetainedValue())
    _fixLifetime(self)
    return result
  }

  @_versioned
  @_inlineable
  @inline(__always)
  internal
  mutating func withMutableASCIIStorage<R>(
    unusedCapacity: Int,
    _ body: (Unmanaged<_ASCIIStringStorage>) -> R
  ) -> R {
    return self.withMutableStorage(
      of: UInt8.self, unusedCapacity: unusedCapacity, body)
  }

  @_versioned
  @_inlineable
  @inline(__always)
  internal
  mutating func withMutableUTF16Storage<R>(
    unusedCapacity: Int,
    _ body: (Unmanaged<_UTF16StringStorage>) -> R
  ) -> R {
    return self.withMutableStorage(
      of: UTF16.CodeUnit.self, unusedCapacity: unusedCapacity, body)
  }
}

//
// String API
//
extension _StringGuts {
  @_versioned
  @_inlineable
  internal var startIndex: Int {
    return 0
  }

  @_versioned
  @_inlineable
  internal var endIndex: Int {
    @inline(__always) get { return count }
  }

  @_inlineable
  public // @testable
  var count: Int {
#if _runtime(_ObjC)
    if _slowPath(_object.isSmall) {
      return _taggedCocoaCount
    }
    if _slowPath(_object.isCocoa) {
      return _cocoaCount
    }
#else
    if _slowPath(_object.isOpaque) {
      return _asOpaque().count
    }
#endif
    _sanityCheck(Int(self._otherBits) >= 0)
    return Int(bitPattern: self._otherBits)
  }

  @_inlineable
  public // @testable
  var capacity: Int {
    if _fastPath(_object.isNative) {
      return _object.nativeRawStorage.capacity
    }
    return 0
  }

  /// Get the UTF-16 code unit stored at the specified position in this string.
  @_inlineable // FIXME(sil-serialize-all)
  public // @testable
  subscript(position: Int) -> UTF16.CodeUnit {
    if _slowPath(_isOpaque) {
      return _asOpaque()[position]
    }

    if isASCII {
      return _unmanagedASCIIView[position]
    }

    return _unmanagedUTF16View[position]
  }

  /// Get the UTF-16 code unit stored at the specified position in this string.
  @_inlineable // FIXME(sil-serialize-all)
  public // @testable
  func codeUnit(atCheckedOffset offset: Int) -> UTF16.CodeUnit {
    if _slowPath(_isOpaque) {
      return _asOpaque().codeUnit(atCheckedOffset: offset)
    } else if isASCII {
      return _unmanagedASCIIView.codeUnit(atCheckedOffset: offset)
    } else {
      return _unmanagedUTF16View.codeUnit(atCheckedOffset: offset)
    }
  }

  // Copy code units from a slice of this string into a buffer.
  @_versioned
  @_inlineable // FIXME(sil-serialize-all)
  internal func _copy<CodeUnit>(
    range: Range<Int>,
    into dest: UnsafeMutableBufferPointer<CodeUnit>)
  where CodeUnit : FixedWidthInteger & UnsignedInteger {
    _sanityCheck(CodeUnit.bitWidth == 8 || CodeUnit.bitWidth == 16)
    _sanityCheck(dest.count >= range.count)
    if _slowPath(_isOpaque) {
      _asOpaque()[range]._copy(into: dest)
      return
    }

    if isASCII {
      _unmanagedASCIIView[range]._copy(into: dest)
    } else {
      _unmanagedUTF16View[range]._copy(into: dest)
    }
  }

  @_inlineable
  public // TODO(StringGuts): for testing
  mutating func reserveUnusedCapacity(
    _ unusedCapacity: Int,
    ascii: Bool = false
  ) {
    if _fastPath(isUniqueNative()) {
      if _fastPath(
        ascii == (_object.bitWidth == 8) &&
        _object.nativeRawStorage.unusedCapacity >= unusedCapacity) {
        return
      }
    }
    if ascii {
      let storage = _copyToNativeStorage(
        of: UInt8.self,
        from: 0..<self.count,
        unusedCapacity: unusedCapacity)
      self = _StringGuts(storage)
    } else {
      let storage = _copyToNativeStorage(
        of: UTF16.CodeUnit.self,
        from: 0..<self.count,
        unusedCapacity: unusedCapacity)
      self = _StringGuts(storage)
    }
    _invariantCheck()
  }

  @_inlineable
  public // TODO(StringGuts): for testing
  mutating func reserveCapacity(_ capacity: Int) {
    if _fastPath(isUniqueNative()) {
      if _fastPath(_object.nativeRawStorage.capacity >= capacity) {
        return
      }
    }
    if isASCII {
      let storage = _copyToNativeStorage(
        of: UInt8.self,
        from: 0..<self.count,
        unusedCapacity: Swift.max(capacity - count, 0))
      self = _StringGuts(storage)
    } else {
      let storage = _copyToNativeStorage(
        of: UTF16.CodeUnit.self,
        from: 0..<self.count,
        unusedCapacity: Swift.max(capacity - count, 0))
      self = _StringGuts(storage)
    }
    _invariantCheck()
  }

  @_versioned
  @_inlineable
  internal
  mutating func append(_ other: _UnmanagedASCIIString) {
    guard other.count > 0 else { return  }
    if _object.isSingleByte {
      withMutableASCIIStorage(unusedCapacity: other.count) { storage in
        storage._value._appendInPlace(other)
      }
    } else {
      withMutableUTF16Storage(unusedCapacity: other.count) { storage in
        storage._value._appendInPlace(other)
      }
    }
  }

  @_versioned
  @_inlineable
  internal
  mutating func append(_ other: _UnmanagedUTF16String) {
    guard other.count > 0 else { return  }
    withMutableUTF16Storage(unusedCapacity: other.count) { storage in
      storage._value._appendInPlace(other)
    }
  }

  @_versioned
  @_inlineable
  internal
  mutating func append(_ other: _UnmanagedOpaqueString) {
    guard other.count > 0 else { return  }
    withMutableUTF16Storage(unusedCapacity: other.count) { storage in
      storage._value._appendInPlace(other)
    }
  }

  @_inlineable
  public // TODO(StringGuts): for testing only
  mutating func append(_ other: _StringGuts) {
    // FIXME(TODO: JIRA): shouldn't _isEmptySingleton be sufficient?
    if _isEmptySingleton || self.count == 0 && !_object.isNative {
      // We must be careful not to discard any capacity that
      // may have been reserved for the append -- this is why
      // we check for the empty string singleton rather than
      // a zero `count` above.
      self = other
      return
    }

    defer { _fixLifetime(other) }
    if _slowPath(other._isOpaque) {
      self.append(other._asOpaque())
    } else if other.isASCII {
      self.append(other._unmanagedASCIIView)
    } else {
      self.append(other._unmanagedUTF16View)
    }
  }

  @_inlineable
  public // TODO(StringGuts): for testing only
  mutating func append(_ other: _StringGuts, range: Range<Int>) {
    _sanityCheck(range.lowerBound >= 0 && range.upperBound <= other.count)
    guard range.count > 0 else { return }
    if _isEmptySingleton && range.count == other.count {
      self = other
      return
    }
    defer { _fixLifetime(other) }
    if _slowPath(other._isOpaque) {
      self.append(other._asOpaque()[range])
    } else if other.isASCII {
      self.append(other._unmanagedASCIIView[range])
    } else {
      self.append(other._unmanagedUTF16View[range])
    }
  }


  //
  // FIXME (TODO JIRA): Appending a character onto the end of a string should
  // really have a less generic implementation, then we can drop @specialize.
  //
  @_specialize(where C == Character._SmallUTF16)
  public // @testable
  mutating func append<C : Collection>(contentsOf other: C)
  where C.Element == UTF16.CodeUnit {
    if _object.isSingleByte && !other.contains(where: { $0 > 0x7f }) {
      withMutableASCIIStorage(
        unusedCapacity: numericCast(other.count)) { storage in
        storage._value._appendInPlaceUTF16(contentsOf: other)
      }
      return
    }
    withMutableUTF16Storage(
      unusedCapacity: numericCast(other.count)) { storage in
      storage._value._appendInPlaceUTF16(contentsOf: other)
    }
  }
}

extension _StringGuts {
  @_versioned
  mutating func _replaceSubrange<C, CodeUnit>(
    _ bounds: Range<Int>,
    with newElements: C,
    of codeUnit: CodeUnit.Type
  ) where C : Collection, C.Element == UTF16.CodeUnit,
  CodeUnit : FixedWidthInteger & UnsignedInteger {
    _precondition(bounds.lowerBound >= 0,
      "replaceSubrange: subrange start precedes String start")

    let newCount: Int = numericCast(newElements.count)
    let deltaCount = newCount - bounds.count
    let paramsOpt = allocationParametersForMutableStorage(
      of: CodeUnit.self,
      unusedCapacity: Swift.max(0, deltaCount))

    if _fastPath(paramsOpt == nil) {
      // We have unique native storage of the correct code unit,
      // with enough capacity to do the replacement inline.
      unowned(unsafe) let storage = _object.nativeStorage(of: CodeUnit.self)
      _sanityCheck(storage.unusedCapacity >= deltaCount)
      let tailCount = storage.count - bounds.upperBound
      _precondition(tailCount >= 0,
        "replaceSubrange: subrange extends past String end")
      let dst = storage.start + bounds.lowerBound
      if deltaCount != 0 && tailCount > 0 {
        // Move tail to make space for new data
        (dst + newCount).moveInitialize(
          from: dst + bounds.count,
          count: tailCount)
      }
      // Copy new elements in place
      var it = newElements.makeIterator()
      for p in dst ..< (dst + newCount) {
        p.pointee = CodeUnit(it.next()!)
      }
      _precondition(it.next() == nil, "Collection misreported its count")
      storage.count += deltaCount
      _nativeCount += deltaCount
      _invariantCheck()
      _fixLifetime(self)
      return
    }

    // Allocate new storage.
    let params = paramsOpt._unsafelyUnwrappedUnchecked
    _precondition(bounds.upperBound <= params.count,
        "replaceSubrange: subrange extends past String end")
    let storage = _SwiftStringStorage<CodeUnit>.create(
      capacity: params.capacity,
      count: params.count + deltaCount)
    var dst = storage.start
    // Copy prefix up to replaced range
    let prefixRange: Range<Int> = 0..<bounds.lowerBound
    _copy(
      range: prefixRange,
      into: UnsafeMutableBufferPointer(start: dst, count: prefixRange.count))
    dst += prefixRange.count

    // Copy new data
    var it = newElements.makeIterator()
    for p in dst ..< (dst + newCount) {
      p.pointee = CodeUnit(it.next()!)
    }
    _precondition(it.next() == nil, "Collection misreported its count")
    dst += newCount

    // Copy suffix from end of replaced range
    let suffixRange: Range<Int> = bounds.upperBound..<params.count
    _copy(
      range: suffixRange,
      into: UnsafeMutableBufferPointer(start: dst, count: suffixRange.count))
    _sanityCheck(dst + suffixRange.count == storage.end)
    self = _StringGuts(storage)
    _invariantCheck()
  }

  public mutating func replaceSubrange<C>(
    _ bounds: Range<Int>,
    with newElements: C
  ) where C : Collection, C.Element == UTF16.CodeUnit {
    if isASCII && !newElements.contains(where: {$0 > 0x7f}) {
      self._replaceSubrange(bounds, with: newElements, of: UInt8.self)
    } else {
      self._replaceSubrange(bounds, with: newElements, of: UTF16.CodeUnit.self)
    }
  }
}

extension _StringGuts : Sequence {
  public typealias Element = UTF16.CodeUnit

  @_fixed_layout
  public struct Iterator : IteratorProtocol {
    public typealias Element = UTF16.CodeUnit

    @_versioned
    internal let _guts: _StringGuts
    @_versioned
    internal let _endOffset: Int
    @_versioned
    internal var _nextOffset: Int
    @_versioned
    internal var _buffer = _FixedArray16<Element>()
    @_versioned
    internal var _bufferIndex: Int = 0

    @_inlineable
    @_versioned
    internal init(_ guts: _StringGuts, range: Range<Int>) {
      self._guts = guts
      self._endOffset = range.upperBound
      self._nextOffset = range.lowerBound
      if _fastPath(!range.isEmpty) {
        _fillBuffer()
      }
    }

    @_inlineable
    public mutating func next() -> Element? {
      if _fastPath(_bufferIndex < _buffer.count) {
        let result = _buffer[_bufferIndex]
        _bufferIndex += 1
        return result
      }
      if _nextOffset == _endOffset {
        return nil
      }
      _fillBuffer()
      _bufferIndex = 1
      return _buffer[0]
    }

    @_versioned
    @inline(never)
    internal mutating func _fillBuffer() {
      _sanityCheck(_buffer.count == 0)
      _buffer.count = Swift.min(_buffer.capacity, _endOffset - _nextOffset)
      _sanityCheck(_buffer.count > 0)
      let guts = _guts // Make a copy to prevent overlapping access to self
      _buffer.withUnsafeMutableBufferPointer { buffer in
        let range: Range<Int> = _nextOffset ..< _nextOffset + buffer.count
        guts._copy(range: range, into: buffer)
      }
      _nextOffset += _buffer.count
    }
  }

  @_inlineable
  public func makeIterator() -> Iterator {
    return Iterator(self, range: 0..<count)
  }

  @_inlineable
  @_versioned
  internal func makeIterator(in range: Range<Int>) -> Iterator {
    return Iterator(self, range: range)
  }
}

extension _StringGuts {
  @_inlineable // FIXME(sil-serialize-all)
  @_versioned // FIXME(sil-serialize-all)
  internal
  static func fromCodeUnits<Input : Sequence, Encoding : _UnicodeEncoding>(
    _ input: Input,
    encoding: Encoding.Type,
    repairIllFormedSequences: Bool,
    minimumCapacity: Int = 0
  ) -> (_StringGuts?, hadError: Bool)
  where Input.Element == Encoding.CodeUnit {
    // Determine how many UTF-16 code units we'll need
    guard let (utf16Count, isASCII) = UTF16.transcodedLength(
      of: input.makeIterator(),
      decodedAs: Encoding.self,
      repairingIllFormedSequences: repairIllFormedSequences) else {
      return (nil, true)
    }
    if isASCII {
      let storage = _SwiftStringStorage<UTF8.CodeUnit>.create(
        capacity: Swift.max(minimumCapacity, utf16Count),
        count: utf16Count)
      let hadError = storage._initialize(
        fromCodeUnits: input,
        encoding: Encoding.self)
      return (_StringGuts(storage), hadError)
    }
    let storage = _SwiftStringStorage<UTF16.CodeUnit>.create(
      capacity: Swift.max(minimumCapacity, utf16Count),
      count: utf16Count)
    let hadError = storage._initialize(
      fromCodeUnits: input,
      encoding: Encoding.self)
    return (_StringGuts(storage), hadError)
  }
}

extension _SwiftStringStorage {
  /// Initialize a piece of freshly allocated storage instance from a sequence
  /// of code units, which is assumed to contain exactly as many code units as
  /// fits in the current storage count.
  ///
  /// Returns true iff `input` was found to contain invalid code units in the
  /// specified encoding. If any invalid sequences are found, they are replaced
  /// with REPLACEMENT CHARACTER (U+FFFD).
  @_inlineable // FIXME(sil-serialize-all)
  @_versioned // FIXME(sil-serialize-all)
  internal
  func _initialize<Input : Sequence, Encoding: _UnicodeEncoding>(
    fromCodeUnits input: Input,
    encoding: Encoding.Type
  ) -> Bool
  where Input.Element == Encoding.CodeUnit {
    var p = self.start
    let hadError = transcode(
      input.makeIterator(),
      from: Encoding.self,
      to: UTF16.self,
      stoppingOnError: false) { cu in
      _sanityCheck(p < end)
      p.pointee = CodeUnit(cu)
      p += 1
    }
    _sanityCheck(p == end)
    return hadError
  }
}

extension String {
  // FIXME: Remove. Still used by swift-corelibs-foundation
  @available(*, deprecated, renamed: "_guts")
  public var _core: _StringGuts {
    return _guts
  }
}

extension _StringGuts {
  // FIXME: Remove. Still used by swift-corelibs-foundation
  @available(*, deprecated)
  public var startASCII: UnsafeMutablePointer<UTF8.CodeUnit> {
    return UnsafeMutablePointer(mutating: _unmanagedASCIIView.start)
  }

  // FIXME: Remove. Still used by swift-corelibs-foundation
  @available(*, deprecated)
  public var startUTF16: UnsafeMutablePointer<UTF16.CodeUnit> {
    return UnsafeMutablePointer(mutating: _unmanagedUTF16View.start)
  }
}
