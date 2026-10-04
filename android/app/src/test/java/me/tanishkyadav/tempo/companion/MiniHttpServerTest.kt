package me.tanishkyadav.tempo.companion

import java.net.HttpURLConnection
import java.net.Socket
import java.net.URL
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

class MiniHttpServerTest {
    private class Fake : MiniHttpServer.Handler {
        var calls = mutableListOf<Pair<Boolean, Int>>()
        var access = true
        override fun status() = MiniHttpServer.Reply(200, """{"ok":true,"dnd_access":$access,"dnd_active":false}""")
        override fun setDnd(on: Boolean, ttlMinutes: Int): MiniHttpServer.Reply {
            if (!access) return MiniHttpServer.Reply(409, """{"ok":false,"error":"dnd_access_denied"}""")
            calls += on to ttlMinutes
            return MiniHttpServer.Reply(200, """{"ok":true}""")
        }
    }

    private val handler = Fake()
    private lateinit var server: MiniHttpServer
    private val token = "s3cret-token"

    @Before fun start() {
        server = MiniHttpServer(0, { token }, handler)
        server.start()
    }

    @After fun stop() = server.stop()

    private fun call(path: String, method: String = "GET", body: String? = null, auth: String? = "Bearer $token"): Pair<Int, String> {
        val c = URL("http://127.0.0.1:${server.boundPort}$path").openConnection() as HttpURLConnection
        c.requestMethod = method
        c.connectTimeout = 3000
        c.readTimeout = 3000
        if (auth != null) c.setRequestProperty("Authorization", auth)
        if (body != null) {
            c.doOutput = true
            c.outputStream.use { it.write(body.toByteArray()) }
        }
        val code = c.responseCode
        val text = (if (code < 400) c.inputStream else c.errorStream).bufferedReader().readText()
        return code to text
    }

    @Test fun statusWithToken() {
        val (code, body) = call("/status")
        assertEquals(200, code)
        assertTrue(body.contains("\"dnd_access\":true"))
    }

    @Test fun rejectsMissingAndWrongToken() {
        assertEquals(401, call("/status", auth = null).first)
        assertEquals(401, call("/status", auth = "Bearer nope").first)
        assertEquals(401, call("/status", auth = token).first) // no "Bearer " prefix
    }

    @Test fun blankServerTokenRejectsEverything() {
        server.stop()
        server = MiniHttpServer(0, { "" }, handler)
        server.start()
        assertEquals(401, call("/status", auth = "Bearer ").first)
    }

    @Test fun dndOnPassesTtl() {
        val (code, _) = call("/dnd", "POST", """{"on":true,"ttl_minutes":55}""")
        assertEquals(200, code)
        assertEquals(listOf(true to 55), handler.calls)
    }

    @Test fun dndOffAndDefaultTtl() {
        call("/dnd", "POST", """{"on": false}""")
        call("/dnd", "POST", """{"on": true}""")
        assertEquals(listOf(false to 60, true to 60), handler.calls)
    }

    @Test fun ttlIsClamped() {
        call("/dnd", "POST", """{"on":true,"ttl_minutes":99999}""")
        call("/dnd", "POST", """{"on":true,"ttl_minutes":0}""")
        assertEquals(listOf(true to 480, true to 1), handler.calls)
    }

    @Test fun missingOnIsBadRequest() {
        assertEquals(400, call("/dnd", "POST", """{"ttl_minutes":5}""").first)
        assertTrue(handler.calls.isEmpty())
    }

    @Test fun accessDeniedIsConflict() {
        handler.access = false
        assertEquals(409, call("/dnd", "POST", """{"on":true}""").first)
    }

    @Test fun unknownRouteAndWrongMethod() {
        assertEquals(404, call("/nope").first)
        assertEquals(404, call("/dnd").first)
        assertEquals(404, call("/status", "POST", "{}").first)
    }

    @Test fun oversizedBodyIsRefused() {
        Socket("127.0.0.1", server.boundPort).use { s ->
            s.getOutputStream().write(
                "POST /dnd HTTP/1.1\r\nAuthorization: Bearer $token\r\nContent-Length: 999999\r\n\r\n".toByteArray()
            )
            val line = s.getInputStream().bufferedReader().readLine()
            assertTrue(line, line.contains("413"))
        }
    }

    @Test fun serverKeepsServingAfterGarbage() {
        Socket("127.0.0.1", server.boundPort).use { it.getOutputStream().write("\u0000\u0001 not http".toByteArray()) }
        assertEquals(200, call("/status").first)
    }
}
