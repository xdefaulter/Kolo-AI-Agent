package com.kolo.agent

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Instrumented tests for the Settings screen UI.
 * These verify navigation from chat to settings and settings content.
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class SettingsInstrumentedTest {

    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val composeTestRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun settingsScreen_navigatesFromChat() {
        // Click settings icon from chat screen
        composeTestRule.onNodeWithContentDescription("Settings").performClick()

        // Wait for navigation
        composeTestRule.waitUntil(timeoutMillis = 3000) {
            composeTestRule.onAllNodesWithText("Settings").fetchSemanticsNodes().isNotEmpty()
        }

        // Should see Settings title
        composeTestRule.onNodeWithText("Settings").assertIsDisplayed()
    }

    @Test
    fun settingsScreen_showsProviderSection() {
        // Navigate to settings
        composeTestRule.onNodeWithContentDescription("Settings").performClick()
        composeTestRule.waitUntil(timeoutMillis = 3000) {
            composeTestRule.onAllNodesWithText("Providers").fetchSemanticsNodes().isNotEmpty()
        }

        // Should see Providers section
        composeTestRule.onNodeWithText("Providers").assertIsDisplayed()
    }

    @Test
    fun settingsScreen_showsToolPermissionsSection() {
        // Navigate to settings
        composeTestRule.onNodeWithContentDescription("Settings").performClick()
        composeTestRule.waitUntil(timeoutMillis = 3000) {
            composeTestRule.onAllNodesWithText("Tool Permissions").fetchSemanticsNodes().isNotEmpty()
        }

        // Tool Permissions should be visible
        composeTestRule.onNodeWithText("Tool Permissions").assertIsDisplayed()
    }
}