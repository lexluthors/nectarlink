// SPDX-License-Identifier: GPL-3.0-or-later
package app.nectarlink.android.mirror

import app.nectarlink.android.elevated.Elevated
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Which typed text goes to the phone as key presses rather than through its
 * clipboard. While the phone is locked, the clipboard can't be read, so the
 * rest goes through the accessibility service instead (see `AppWindows`).
 */
class TypingTextTest {
    @Test
    fun plainLettersAndSymbolsAreTyped() {
        for (text in listOf("a", "Z", "7", " ", "~", "!")) {
            assertTrue("'$text'", Elevated.typesAsKeys(text))
        }
    }

    @Test
    fun enterIsTyped() {
        for (text in listOf("\n", "\r", "\r\n")) {
            assertTrue("'$text'", Elevated.typesAsKeys(text))
        }
    }

    @Test
    fun wordsAndNonAsciiNeedTheClipboard() {
        for (text in listOf("ab", "hello", "你好", "🙂", "a你", "\t")) {
            assertFalse("'$text'", Elevated.typesAsKeys(text))
        }
    }

    @Test
    fun nothingToTypeCountsAsTyped() {
        assertTrue(Elevated.typesAsKeys(""))
    }
}