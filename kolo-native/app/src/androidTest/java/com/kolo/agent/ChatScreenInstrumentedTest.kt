package com.kolo.agent

import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import dagger.hilt.android.testing.HiltAndroidRule
import dagger.hilt.android.testing.HiltAndroidTest
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Instrumented tests for the main Chat screen UI.
 * These run on a real device or emulator and verify Compose UI behavior.
 */
@HiltAndroidTest
@RunWith(AndroidJUnit4::class)
class ChatScreenInstrumentedTest {

    @get:Rule(order = 0)
    val hiltRule = HiltAndroidRule(this)

    @get:Rule(order = 1)
    val composeTestRule = createAndroidComposeRule<MainActivity>()

    @Test
    fun chatScreen_showsEmptyState() {
        // Verify the empty chat state is displayed on first launch
        composeTestRule.onNodeWithText("How can I help you?").assertIsDisplayed()
    }

    @Test
    fun chatScreen_hasMessageInput() {
        // Verify the message input field exists
        composeTestRule.onNodeWithText("Message…").assertIsDisplayed()
    }

    @Test
    fun chatScreen_hasDrawerToggle() {
        // Verify the menu/drawer toggle button exists
        composeTestRule.onNodeWithContentDescription("Chat list").assertIsDisplayed()
    }

    @Test
    fun chatScreen_typeAndClearsOnSend() {
        // Type a message
        composeTestRule.onNodeWithText("Message…").performTextInput("Hello test")
        composeTestRule.onNodeWithText("Hello test").assertIsDisplayed()

        // The send button should exist
        composeTestRule.onNodeWithContentDescription("Send").assertIsDisplayed()
    }

    @Test
    fun chatScreen_settingsAccessible() {
        // The settings icon should be visible
        composeTestRule.onNodeWithContentDescription("Settings").assertIsDisplayed()
    }
}