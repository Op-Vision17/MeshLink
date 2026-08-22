package com.meshlink.meshlink.mesh

sealed class BleResult {
    object Success : BleResult()
    object BluetoothDisabled : BleResult()
    data class PermissionDenied(val permission: String) : BleResult()
    data class Error(val reason: String) : BleResult()

    val isSuccess: Boolean get() = this is Success

    fun toErrorCode(): String = when (this) {
        is Success -> "OK"
        is BluetoothDisabled -> "BLUETOOTH_DISABLED"
        is PermissionDenied -> "PERMISSION_DENIED:$permission"
        is Error -> "ERROR:$reason"
    }
}
