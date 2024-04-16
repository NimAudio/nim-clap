import math


type
    Changed*[T] = object
        has_changed *: bool
        value       *: T
        # raw_value   *: T
        # on_changed  *: proc (raw, old: T): T

converter changed_from_value*[T](value: T): Changed[T] =
    result = Changed[T](
        has_changed: true,
        value: value,
        # raw_value: value,
        # on_changed: nil
    )

# proc `=sink`*[T](dst: var Changed[T], src: Changed[T]): void =
#     if (dst.raw_value != src.raw_value) and (dst.raw_value != nil or dst.value != nil):
#         var new_value = if dst.on_changed != nil:
#                             dst.on_changed(src.raw_value, dst.raw_value)
#                         else:
#                             src.raw_value
#         `=destroy`(dst.value)
#         `=destroy`(dst.raw_value)
#         dst.value = new_value
#         dst.raw_value = src.raw_value

converter changed_value*[T](changed: Changed[T]): T =
    result = changed.value

converter changed_changed*[T](changed: Changed[T]): bool =
    result = changed.has_changed

proc `<-`*[T](c_to, c_from: var Changed[T]): void =
    if c_from.changed:
        c_from.has_changed = false
        c_to = c_from



type
    AutoDB* = object
        internal_db *: float64
        internal_af *: float64
    ChangedAutoDB* = object
        has_changed *: bool
        internal_db *: float64
        internal_af *: float64
    SomeAutoDB* = AutoDB | ChangedAutoDB

proc db_af*(db: float64): float64 =
    result = pow(10, 0.05 * db)

proc af_db*(af: float64): float64 =
    result = 20 * log10(af)

proc db*(adb: SomeAutoDB): float64 =
    result = adb.internal_db

proc af*(adb: SomeAutoDB): float64 =
    result = adb.internal_af

proc `=db`*(adb: var AutoDB, value: float64): float64 =
    adb.internal_db = value
    adb.internal_af = db_af(value)

proc `=af`*(adb: var AutoDB, value: float64): float64 =
    adb.internal_db = af_db(value)
    adb.internal_af = value

proc `=db`*(adb: var ChangedAutoDB, value: float64): float64 =
    adb.internal_db = value
    adb.internal_af = db_af(value)
    adb.has_changed = true

proc `=af`*(adb: var ChangedAutoDB, value: float64): float64 =
    adb.internal_db = af_db(value)
    adb.internal_af = value
    adb.has_changed = true
