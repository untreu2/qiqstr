package me.untreu.qiqstr.core

import com.qiqstr.core.QiqException

class CoreError(message: String) : Exception(message)

fun coreErrorMessage(error: Throwable): String = when (error) {
    is QiqException.Failed -> error.reason
    else -> error.message ?: error.toString()
}
