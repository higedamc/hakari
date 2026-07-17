package org.lekt.hakari

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the NIP-55 (Amber external signer) bridge for the
 * `org.lekt.hakari/amber` MethodChannel.
 *
 * Foreground flow: launch Amber (com.greenart7c3.nostrsigner) via
 * ACTION_VIEW on a `nostrsigner:` URI with startActivityForResult, keep the
 * pending MethodChannel.Result in a requestCode-keyed map, and resolve it in
 * onActivityResult from the "result" / "signature" / "event" / "rejected"
 * extras.
 *
 * Background flow (only works after the user grants "always allow" in
 * Amber): ContentProvider queries against
 * content://com.greenart7c3.nostrsigner.<SIGN_EVENT|NIP44_ENCRYPT|NIP44_DECRYPT>.
 */
class MainActivity : FlutterFragmentActivity() {
    companion object {
        private const val TAG = "MainActivity"
        private const val AMBER_CHANNEL = "org.lekt.hakari/amber"
        private const val AMBER_PACKAGE = "com.greenart7c3.nostrsigner"
        private const val APP_NAME = "hakari"
        private const val AMBER_REQUEST_CODE_BASE = 9200
        private const val AMBER_REQUEST_CODE_MAX = 9299

        /**
         * SHA-256 digests of Amber's known signing certificates (both
         * signed by greenart7c3; extracted with `apksigner verify
         * --print-certs` from the v6.2.3 release APKs). Package names can
         * be squatted by sideloaded apps — health data and pubkey trust
         * must not leave this app unless the installed package is signed
         * by one of these.
         */
        private val AMBER_CERT_SHA256_ALLOWLIST = setOf(
            // GitHub releases / zapstore ("play" flavor)
            "e8ab8c69333b68636dd46ce242408c79553a7fd9055d054d61daababada53bbf",
            // F-Droid flavor (reproducible, developer-signed)
            "56dc631996a55c2284790448c7dc9f1dd05df596b2ce4882313633f5602e5fe4",
        )
    }

    /** requestCode -> (pending Flutter result, NIP-55 request type). */
    private val pendingResults =
        mutableMapOf<Int, Pair<MethodChannel.Result, String>>()
    private var nextRequestCode = AMBER_REQUEST_CODE_BASE

    /** Single thread for Amber ContentProvider queries (never the UI thread). */
    private val amberQueryExecutor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AMBER_CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAmberInstalled" -> result.success(isAmberInstalled())

                "getPublicKeyFromAmber" -> {
                    // NIP-55 get_public_key. Requesting permissions up front
                    // lets Amber register the app and remember approvals.
                    val permissionsJson =
                        """[{"type":"get_public_key"},{"type":"sign_event"},{"type":"nip44_encrypt"},{"type":"nip44_decrypt"}]"""
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        data = Uri.parse("nostrsigner:")
                        `package` = AMBER_PACKAGE
                        putExtra("type", "get_public_key")
                        putExtra("package", packageName)
                        putExtra("appName", APP_NAME)
                        putExtra("permissions", permissionsJson)
                    }
                    launchAmber(intent, "get_public_key", result)
                }

                "signEventWithAmber" -> {
                    val eventJson = call.argument<String>("event")
                    if (eventJson == null) {
                        result.error(
                            "INVALID_ARGUMENT",
                            "event parameter is required",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        data = Uri.parse("nostrsigner:$eventJson")
                        `package` = AMBER_PACKAGE
                        putExtra("type", "sign_event")
                        putExtra("package", packageName)
                        putExtra("appName", APP_NAME)
                    }
                    launchAmber(intent, "sign_event", result)
                }

                "nip44EncryptWithAmber" -> {
                    val plaintext = call.argument<String>("plaintext")
                    val pubkey = call.argument<String>("pubkey")
                    if (plaintext == null || pubkey == null) {
                        result.error(
                            "INVALID_ARGUMENT",
                            "plaintext and pubkey parameters are required",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        data = Uri.parse("nostrsigner:$plaintext")
                        `package` = AMBER_PACKAGE
                        putExtra("type", "nip44_encrypt")
                        putExtra("pubkey", pubkey)
                        putExtra("package", packageName)
                        putExtra("appName", APP_NAME)
                    }
                    launchAmber(intent, "nip44_encrypt", result)
                }

                "nip44DecryptWithAmber" -> {
                    val ciphertext = call.argument<String>("ciphertext")
                    val pubkey = call.argument<String>("pubkey")
                    if (ciphertext == null || pubkey == null) {
                        result.error(
                            "INVALID_ARGUMENT",
                            "ciphertext and pubkey parameters are required",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        data = Uri.parse("nostrsigner:$ciphertext")
                        `package` = AMBER_PACKAGE
                        putExtra("type", "nip44_decrypt")
                        putExtra("pubkey", pubkey)
                        putExtra("package", packageName)
                        putExtra("appName", APP_NAME)
                    }
                    launchAmber(intent, "nip44_decrypt", result)
                }

                // -------- ContentProvider fallback (background, no UI) -----
                // Works only when the corresponding permission is set to
                // "always allow" inside Amber; otherwise returns
                // AMBER_REJECTED and the caller must retry with the
                // foreground intent flow.

                "signEventWithAmberContentProvider" -> {
                    val eventJson = call.argument<String>("event")
                    val npub = call.argument<String>("npub")
                    if (eventJson == null || npub == null) {
                        result.error(
                            "INVALID_ARGUMENT",
                            "event and npub parameters are required",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    queryAmberContentProvider(
                        uri = "content://$AMBER_PACKAGE.SIGN_EVENT",
                        projection = arrayOf(eventJson, "", npub),
                        resultColumns = listOf("event", "signature", "result"),
                        result = result
                    )
                }

                "nip44EncryptWithAmberContentProvider" -> {
                    val plaintext = call.argument<String>("plaintext")
                    val pubkey = call.argument<String>("pubkey")
                    val npub = call.argument<String>("npub")
                    if (plaintext == null || pubkey == null || npub == null) {
                        result.error(
                            "INVALID_ARGUMENT",
                            "plaintext, pubkey and npub parameters are required",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    queryAmberContentProvider(
                        uri = "content://$AMBER_PACKAGE.NIP44_ENCRYPT",
                        projection = arrayOf(plaintext, pubkey, npub),
                        resultColumns = listOf("result", "signature"),
                        result = result
                    )
                }

                "nip44DecryptWithAmberContentProvider" -> {
                    val ciphertext = call.argument<String>("ciphertext")
                    val pubkey = call.argument<String>("pubkey")
                    val npub = call.argument<String>("npub")
                    if (ciphertext == null || pubkey == null || npub == null) {
                        result.error(
                            "INVALID_ARGUMENT",
                            "ciphertext, pubkey and npub parameters are required",
                            null
                        )
                        return@setMethodCallHandler
                    }
                    queryAmberContentProvider(
                        uri = "content://$AMBER_PACKAGE.NIP44_DECRYPT",
                        projection = arrayOf(ciphertext, pubkey, npub),
                        resultColumns = listOf("result", "signature"),
                        result = result
                    )
                }

                else -> result.notImplemented()
            }
        }
    }

    /**
     * True when the pinned Amber package is installed AND signed by a
     * known greenart7c3 certificate. Every launch is pinned to
     * [AMBER_PACKAGE], so a generic "anything handles nostrsigner:"
     * check would report signers we never actually talk to.
     */
    private fun isAmberInstalled(): Boolean = verifyAmberSignature() == null

    /**
     * Verifies the installed Amber package against
     * [AMBER_CERT_SHA256_ALLOWLIST].
     *
     * @return null when trusted; otherwise a human-readable reason
     * (not installed / unrecognized signature). Callers must refuse to
     * send data to Amber unless this returns null.
     */
    private fun verifyAmberSignature(): String? {
        val signatures = try {
            if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.P) {
                val info = packageManager.getPackageInfo(
                    AMBER_PACKAGE,
                    android.content.pm.PackageManager.GET_SIGNING_CERTIFICATES
                )
                val signingInfo = info.signingInfo ?: return "Amber has no signing info"
                if (signingInfo.hasMultipleSigners()) {
                    signingInfo.apkContentsSigners
                } else {
                    signingInfo.signingCertificateHistory
                }
            } else {
                @Suppress("DEPRECATION")
                val info = packageManager.getPackageInfo(
                    AMBER_PACKAGE,
                    android.content.pm.PackageManager.GET_SIGNATURES
                )
                @Suppress("DEPRECATION")
                info.signatures
            }
        } catch (e: android.content.pm.PackageManager.NameNotFoundException) {
            return "Amber is not installed"
        } catch (e: Exception) {
            android.util.Log.w(TAG, "Amber signature lookup failed", e)
            return "Amber signature lookup failed"
        }
        if (signatures.isNullOrEmpty()) return "Amber has no signatures"

        val digest = java.security.MessageDigest.getInstance("SHA-256")
        val observed = signatures.map { sig ->
            digest.digest(sig.toByteArray()).joinToString("") { "%02x".format(it) }
        }
        // Multi-signer APKs are trusted only if EVERY signer is known;
        // single/rotated certs are trusted if ANY history entry is known.
        val trusted = if (observed.size > 1) {
            observed.all { it in AMBER_CERT_SHA256_ALLOWLIST }
        } else {
            observed.any { it in AMBER_CERT_SHA256_ALLOWLIST }
        }
        if (!trusted) {
            android.util.Log.e(
                TAG,
                "Installed $AMBER_PACKAGE has unrecognized signing cert(s): $observed"
            )
            return "Installed Amber has an unrecognized signature"
        }
        return null
    }

    /**
     * Runs [verifyAmberSignature] and fails [result] with AMBER_UNTRUSTED
     * when the installed package cannot be trusted. Returns true when it
     * is safe to proceed.
     */
    private fun requireTrustedAmber(result: MethodChannel.Result): Boolean {
        val reason = verifyAmberSignature() ?: return true
        result.error("AMBER_UNTRUSTED", reason, null)
        return false
    }

    /**
     * Fire an Amber intent with startActivityForResult, parking [result]
     * under a fresh request code until onActivityResult resolves it.
     */
    private fun launchAmber(
        intent: Intent,
        requestType: String,
        result: MethodChannel.Result
    ) {
        if (!requireTrustedAmber(result)) return
        val requestCode = nextRequestCode
        nextRequestCode =
            if (nextRequestCode >= AMBER_REQUEST_CODE_MAX) AMBER_REQUEST_CODE_BASE
            else nextRequestCode + 1
        // Resolve any leaked slot from a never-returning Amber launch so
        // a request-code wrap cannot deliver a stale result to the wrong
        // caller (Dart has long since timed out on it).
        pendingResults.remove(requestCode)?.first?.error(
            "AMBER_STALE",
            "Superseded by a newer Amber request",
            null
        )
        pendingResults[requestCode] = Pair(result, requestType)
        try {
            android.util.Log.d(
                TAG,
                "Launching Amber: type=$requestType requestCode=$requestCode"
            )
            @Suppress("DEPRECATION")
            startActivityForResult(intent, requestCode)
        } catch (e: ActivityNotFoundException) {
            android.util.Log.e(TAG, "Amber not installed", e)
            pendingResults.remove(requestCode)
            result.error("AMBER_NOT_INSTALLED", "Amber is not installed", null)
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Failed to launch Amber", e)
            pendingResults.remove(requestCode)
            result.error(
                "AMBER_ERROR",
                "Failed to launch Amber: ${e.message}",
                null
            )
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        val pending = pendingResults.remove(requestCode) ?: return
        val (pendingResult, requestType) = pending
        android.util.Log.d(
            TAG,
            "onActivityResult: type=$requestType requestCode=$requestCode resultCode=$resultCode"
        )

        if (resultCode != RESULT_OK || data == null) {
            pendingResult.error(
                "AMBER_CANCELLED",
                "Request was cancelled",
                null
            )
            return
        }

        // Amber puts the payload in "result" (pubkey / ciphertext /
        // plaintext) or "signature"; sign_event additionally gets the full
        // signed event JSON in "event". Rejection arrives as a "rejected"
        // extra, errors as "error".
        val rejected = data.getStringExtra("rejected")
        val error = data.getStringExtra("error")
        val resultExtra =
            data.getStringExtra("result") ?: data.getStringExtra("signature")
        val signedEvent = data.getStringExtra("event")

        when {
            rejected != null -> {
                android.util.Log.w(TAG, "User rejected the request in Amber")
                pendingResult.error(
                    "AMBER_REJECTED",
                    "User rejected the request",
                    null
                )
            }

            error != null -> {
                android.util.Log.e(TAG, "Amber returned error: $error")
                pendingResult.error("AMBER_ERROR", error, null)
            }

            resultExtra != null || signedEvent != null -> {
                // sign_event prefers the full signed event JSON; every other
                // type ("get_public_key", "nip44_encrypt", "nip44_decrypt")
                // uses the plain result string.
                val responseValue = when (requestType) {
                    "sign_event" -> signedEvent ?: resultExtra
                    else -> resultExtra ?: signedEvent
                }
                if (responseValue.isNullOrEmpty()) {
                    pendingResult.error(
                        "AMBER_ERROR",
                        "Empty response from Amber",
                        null
                    )
                } else {
                    pendingResult.success(responseValue)
                }
            }

            else -> {
                pendingResult.error(
                    "AMBER_ERROR",
                    "No valid response from Amber",
                    null
                )
            }
        }
    }

    /**
     * Query Amber's ContentProvider (background path). Responds with the
     * first non-null value among [resultColumns], AMBER_REJECTED when the
     * "rejected" column is present, or AMBER_ERROR otherwise.
     */
    private fun queryAmberContentProvider(
        uri: String,
        projection: Array<String>,
        resultColumns: List<String>,
        result: MethodChannel.Result
    ) {
        if (!requireTrustedAmber(result)) return
        // ContentResolver.query can block while Amber's process spins up;
        // run it off the platform thread and reply via the main looper
        // (MethodChannel.Result must be answered on the platform thread).
        val mainHandler = Handler(Looper.getMainLooper())
        amberQueryExecutor.execute {
            queryAmberContentProviderBlocking(uri, projection, resultColumns) {
                block -> mainHandler.post { block(result) }
            }
        }
    }

    /** Runs the blocking query; [reply] posts result callbacks to main. */
    private fun queryAmberContentProviderBlocking(
        uri: String,
        projection: Array<String>,
        resultColumns: List<String>,
        reply: ((MethodChannel.Result) -> Unit) -> Unit
    ) {
        try {
            val cursor = contentResolver.query(
                Uri.parse(uri),
                projection,
                null,
                null,
                null
            )
            if (cursor == null) {
                reply { r ->
                    r.error(
                        "AMBER_ERROR",
                        "No response from Amber ContentProvider",
                        null
                    )
                }
                return
            }
            cursor.use {
                if (!it.moveToFirst()) {
                    reply { r ->
                        r.error(
                            "AMBER_ERROR",
                            "No response from Amber ContentProvider",
                            null
                        )
                    }
                    return
                }
                if (it.getColumnIndex("rejected") >= 0) {
                    reply { r ->
                        r.error(
                            "AMBER_REJECTED",
                            "Permission not granted. User needs to approve in Amber.",
                            null
                        )
                    }
                    return
                }
                for (column in resultColumns) {
                    val index = it.getColumnIndex(column)
                    if (index >= 0) {
                        val value = it.getString(index)
                        if (!value.isNullOrEmpty()) {
                            reply { r -> r.success(value) }
                            return
                        }
                    }
                }
                reply { r ->
                    r.error(
                        "AMBER_ERROR",
                        "No valid response from Amber ContentProvider",
                        null
                    )
                }
            }
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Amber ContentProvider query failed", e)
            reply { r ->
                r.error(
                    "AMBER_ERROR",
                    "Amber ContentProvider query failed: ${e.message}",
                    null
                )
            }
        }
    }
}
