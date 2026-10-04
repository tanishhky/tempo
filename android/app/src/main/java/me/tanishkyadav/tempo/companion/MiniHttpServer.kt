package me.tanishkyadav.tempo.companion

import java.io.BufferedInputStream
import java.io.InputStream
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketException
import java.security.MessageDigest

/**
 * A deliberately tiny HTTP/1.1 server: two routes, bearer-token auth, one request per connection.
 * It has no Android dependencies so it can be unit tested on the JVM.
 */
class MiniHttpServer(
    private val port: Int,
    private val token: () -> String,
    private val handler: Handler,
) {
    interface Handler {
        fun status(): Reply
        fun setDnd(on: Boolean, ttlMinutes: Int): Reply
    }

    data class Reply(val code: Int, val body: String)

    @Volatile private var server: ServerSocket? = null

    val boundPort: Int get() = server?.localPort ?: port

    fun start() {
        val s = ServerSocket(port, 8)
        server = s
        Thread({ loop(s) }, "tempo-http").apply { isDaemon = true }.start()
    }

    fun stop() {
        server?.close()
        server = null
    }

    private fun loop(s: ServerSocket) {
        while (!s.isClosed) {
            try {
                s.accept().use { serve(it) }
            } catch (_: SocketException) {
                // closed
            } catch (_: Exception) {
                Thread.sleep(50)
            }
        }
    }

    private fun serve(sock: Socket) {
        sock.soTimeout = 3000
        val input = BufferedInputStream(sock.getInputStream())
        val requestLine = readLine(input) ?: return
        val parts = requestLine.split(" ")
        if (parts.size < 2) return respond(sock, Reply(400, error("bad_request")))

        val headers = HashMap<String, String>()
        while (true) {
            val line = readLine(input) ?: return
            if (line.isEmpty()) break
            val i = line.indexOf(':')
            if (i > 0) headers[line.substring(0, i).trim().lowercase()] = line.substring(i + 1).trim()
            if (headers.size > 40) return
        }

        val length = headers["content-length"]?.toIntOrNull() ?: 0
        if (length < 0 || length > MAX_BODY) return respond(sock, Reply(413, error("too_large")))
        val body = ByteArray(length)
        var read = 0
        while (read < length) {
            val n = input.read(body, read, length - read)
            if (n < 0) break
            read += n
        }

        val secret = token()
        val given = headers["authorization"] ?: ""
        val authorised = secret.isNotBlank() &&
            MessageDigest.isEqual(given.toByteArray(), "Bearer $secret".toByteArray())
        if (!authorised) {
            Thread.sleep(300) // slow down guessing
            return respond(sock, Reply(401, error("unauthorized")))
        }

        val path = parts[1].substringBefore('?')
        val reply = when {
            parts[0] == "GET" && path == "/status" -> handler.status()
            parts[0] == "POST" && path == "/dnd" -> {
                val text = String(body, 0, read)
                val on = ON.find(text)?.groupValues?.get(1)
                if (on == null) {
                    Reply(400, error("missing_on"))
                } else {
                    val ttl = TTL.find(text)?.groupValues?.get(1)?.toIntOrNull() ?: 60
                    handler.setDnd(on == "true", ttl.coerceIn(1, 480))
                }
            }
            else -> Reply(404, error("not_found"))
        }
        respond(sock, reply)
    }

    private fun readLine(input: InputStream): String? {
        val sb = StringBuilder()
        while (sb.length < 8192) {
            val c = input.read()
            if (c < 0) return if (sb.isEmpty()) null else sb.toString()
            if (c == '\n'.code) return sb.toString().trimEnd('\r')
            sb.append(c.toChar())
        }
        return null
    }

    private fun respond(sock: Socket, reply: Reply) {
        val payload = reply.body.toByteArray()
        val head = "HTTP/1.1 ${reply.code} ${reason(reply.code)}\r\n" +
            "Content-Type: application/json\r\n" +
            "Content-Length: ${payload.size}\r\n" +
            "Connection: close\r\n\r\n"
        sock.getOutputStream().apply {
            write(head.toByteArray())
            write(payload)
            flush()
        }
    }

    private fun reason(code: Int) = when (code) {
        200 -> "OK"
        400 -> "Bad Request"
        401 -> "Unauthorized"
        404 -> "Not Found"
        409 -> "Conflict"
        413 -> "Payload Too Large"
        else -> "Error"
    }

    private fun error(code: String) = """{"ok":false,"error":"$code"}"""

    private companion object {
        const val MAX_BODY = 4096
        val ON = Regex("\"on\"\\s*:\\s*(true|false)")
        val TTL = Regex("\"ttl_minutes\"\\s*:\\s*(\\d+)")
    }
}
