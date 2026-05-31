package com.kolo.agent.di

import com.kolo.agent.core.model.MemoryRepository
import com.kolo.agent.core.tools.registry.ToolRegistry
import com.kolo.agent.feature.phonecontrol.*
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object ToolModule {

    @Provides
    @Singleton
    fun provideToolRegistry(
        memoryRepository: MemoryRepository,
    ): ToolRegistry = ToolRegistry().also { registry ->
        // Wire memory tools to the repository
        (registry.getTool("recall_memories") as? com.kolo.agent.core.tools.builtin.RecallMemoriesTool)?.memoryRepository = memoryRepository
        (registry.getTool("remember_this") as? com.kolo.agent.core.tools.builtin.RememberThisTool)?.memoryRepository = memoryRepository
        (registry.getTool("forget_memory") as? com.kolo.agent.core.tools.builtin.ForgetMemoryTool)?.memoryRepository = memoryRepository

        // Phone control tools
        registry.register(ScreenReadTool())
        registry.register(TapTool())
        registry.register(SwipeTool())
        registry.register(LongPressTool())
        registry.register(ClickTextTool())
        registry.register(TypeTextTool())
        registry.register(PressKeyTool())
        registry.register(ScrollTool())
        registry.register(ScreenReadFullTool())
        registry.register(ShowActionTool())
        registry.register(PhoneControlStartTool())
        registry.register(PhoneControlStatusTool())
        registry.register(PhoneControlDoneTool())
    }
}