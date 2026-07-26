package com.agentgrid.mobile.network

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

object PhoneSessionFactory {
    fun create(context: Context, deviceID: String): PhoneSession =
        DefaultPhoneSession(
            credentialStore = PairingStore(context.applicationContext),
            transport = OkHttpPhoneSessionTransport(),
            deviceID = deviceID,
            scope = CoroutineScope(SupervisorJob() + Dispatchers.IO),
        )
}
