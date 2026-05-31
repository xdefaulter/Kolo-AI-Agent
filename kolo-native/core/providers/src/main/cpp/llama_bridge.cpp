#include <android/log.h>
#include <jni.h>

#include <algorithm>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#include "common.h"
#include "llama.h"
#include "sampling.h"

#define LOG_TAG "KoloLlamaBridge"

namespace {

constexpr int BATCH_SIZE = 512;
constexpr int CONTEXT_HEADROOM = 4;

std::once_flag backend_init_flag;

void android_log_callback(ggml_log_level level, const char * text, void * /*user_data*/) {
    int android_level = ANDROID_LOG_DEBUG;
    if (level == GGML_LOG_LEVEL_ERROR) android_level = ANDROID_LOG_ERROR;
    if (level == GGML_LOG_LEVEL_WARN) android_level = ANDROID_LOG_WARN;
    if (level == GGML_LOG_LEVEL_INFO) android_level = ANDROID_LOG_INFO;
    __android_log_write(android_level, LOG_TAG, text);
}

void init_backend_once() {
    std::call_once(backend_init_flag, [] {
        llama_log_set(android_log_callback, nullptr);
        llama_backend_init();
        __android_log_write(ANDROID_LOG_INFO, LOG_TAG, "llama.cpp backend initialized");
    });
}

struct KoloLlamaState {
    llama_model * model = nullptr;
    llama_context * context = nullptr;
    llama_batch batch {};
    bool batch_initialized = false;
    int n_ctx = 4096;
    int n_threads = 4;
};

std::string get_jstring(JNIEnv * env, jstring value) {
    if (value == nullptr) return "";
    const char * chars = env->GetStringUTFChars(value, nullptr);
    std::string result(chars == nullptr ? "" : chars);
    if (chars != nullptr) {
        env->ReleaseStringUTFChars(value, chars);
    }
    return result;
}

void free_state(KoloLlamaState * state) {
    if (state == nullptr) return;
    if (state->batch_initialized) {
        llama_batch_free(state->batch);
        state->batch_initialized = false;
    }
    if (state->context != nullptr) {
        llama_free(state->context);
        state->context = nullptr;
    }
    if (state->model != nullptr) {
        llama_model_free(state->model);
        state->model = nullptr;
    }
    delete state;
}

int decode_tokens(
        llama_context * context,
        llama_batch & batch,
        const llama_tokens & tokens,
        llama_pos start_pos,
        int n_ctx) {
    for (int i = 0; i < static_cast<int>(tokens.size()); i += BATCH_SIZE) {
        const int cur_batch_size = std::min(static_cast<int>(tokens.size()) - i, BATCH_SIZE);
        common_batch_clear(batch);

        if (start_pos + i + cur_batch_size >= n_ctx - CONTEXT_HEADROOM) {
            return 1;
        }

        for (int j = 0; j < cur_batch_size; ++j) {
            const bool logits = (i + j == static_cast<int>(tokens.size()) - 1);
            common_batch_add(batch, tokens[i + j], start_pos + i + j, {0}, logits);
        }

        if (llama_decode(context, batch) != 0) {
            return 2;
        }
    }
    return 0;
}

}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_kolo_agent_core_providers_local_LlamaCppBridge_nativeRuntimeAvailable(
        JNIEnv *,
        jobject) {
    init_backend_once();
    return JNI_TRUE;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_kolo_agent_core_providers_local_LlamaCppBridge_nativeLoadModel(
        JNIEnv * env,
        jobject,
        jstring jmodel_path,
        jint context_size,
        jint threads) {
    init_backend_once();

    const std::string model_path = get_jstring(env, jmodel_path);
    llama_model_params model_params = llama_model_default_params();
    llama_model * model = llama_model_load_from_file(model_path.c_str(), model_params);
    if (model == nullptr) {
        __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, "Failed to load model: %s", model_path.c_str());
        return 0L;
    }

    const int n_ctx = std::max(512, static_cast<int>(context_size));
    const int n_threads = std::max(1, static_cast<int>(threads));

    llama_context_params ctx_params = llama_context_default_params();
    ctx_params.n_ctx = n_ctx;
    ctx_params.n_batch = BATCH_SIZE;
    ctx_params.n_ubatch = BATCH_SIZE;
    ctx_params.n_threads = n_threads;
    ctx_params.n_threads_batch = n_threads;

    llama_context * context = llama_init_from_model(model, ctx_params);
    if (context == nullptr) {
        __android_log_write(ANDROID_LOG_ERROR, LOG_TAG, "Failed to initialize llama context");
        llama_model_free(model);
        return 0L;
    }

    auto * state = new KoloLlamaState();
    state->model = model;
    state->context = context;
    state->batch = llama_batch_init(BATCH_SIZE, 0, 1);
    state->batch_initialized = true;
    state->n_ctx = n_ctx;
    state->n_threads = n_threads;
    return reinterpret_cast<jlong>(state);
}

extern "C" JNIEXPORT void JNICALL
Java_com_kolo_agent_core_providers_local_LlamaCppBridge_nativeUnloadModel(
        JNIEnv *,
        jobject,
        jlong handle) {
    free_state(reinterpret_cast<KoloLlamaState *>(handle));
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_kolo_agent_core_providers_local_LlamaCppBridge_nativeComplete(
        JNIEnv * env,
        jobject,
        jlong handle,
        jstring jprompt,
        jint max_tokens,
        jfloat temperature,
        jfloat top_p,
        jfloat repeat_penalty) {
    auto * state = reinterpret_cast<KoloLlamaState *>(handle);
    if (state == nullptr || state->model == nullptr || state->context == nullptr) {
        return env->NewStringUTF("Local llama.cpp model is not loaded.");
    }

    const std::string prompt = get_jstring(env, jprompt);
    if (prompt.empty()) {
        return env->NewStringUTF("");
    }

    llama_memory_clear(llama_get_memory(state->context), false);

    llama_tokens prompt_tokens = common_tokenize(state->context, prompt, true, true);
    if (prompt_tokens.empty()) {
        return env->NewStringUTF("");
    }

    const int max_prompt_tokens = state->n_ctx - CONTEXT_HEADROOM - 1;
    if (static_cast<int>(prompt_tokens.size()) > max_prompt_tokens) {
        prompt_tokens.erase(
                prompt_tokens.begin(),
                prompt_tokens.end() - max_prompt_tokens);
    }

    const int decode_result = decode_tokens(
            state->context,
            state->batch,
            prompt_tokens,
            0,
            state->n_ctx);
    if (decode_result != 0) {
        std::string error = "llama.cpp prompt decode failed: " + std::to_string(decode_result);
        return env->NewStringUTF(error.c_str());
    }

    common_params_sampling sampling_params;
    sampling_params.temp = temperature;
    sampling_params.top_p = top_p;
    sampling_params.penalty_repeat = repeat_penalty;
    common_sampler * sampler = common_sampler_init(state->model, sampling_params);
    if (sampler == nullptr) {
        return env->NewStringUTF("Failed to initialize llama.cpp sampler.");
    }

    std::ostringstream output;
    std::string cached_utf8;
    llama_pos current_pos = static_cast<llama_pos>(prompt_tokens.size());
    const int n_predict = std::max(1, static_cast<int>(max_tokens));

    for (int i = 0; i < n_predict; ++i) {
        if (current_pos >= state->n_ctx - CONTEXT_HEADROOM) {
            break;
        }

        const llama_token token = common_sampler_sample(sampler, state->context, -1);
        common_sampler_accept(sampler, token, true);

        if (llama_vocab_is_eog(llama_model_get_vocab(state->model), token)) {
            break;
        }

        cached_utf8 += common_token_to_piece(state->context, token);
        output << cached_utf8;
        cached_utf8.clear();

        common_batch_clear(state->batch);
        common_batch_add(state->batch, token, current_pos, {0}, true);
        if (llama_decode(state->context, state->batch) != 0) {
            break;
        }
        current_pos++;
    }

    common_sampler_free(sampler);
    const std::string result = output.str();
    return env->NewStringUTF(result.c_str());
}
