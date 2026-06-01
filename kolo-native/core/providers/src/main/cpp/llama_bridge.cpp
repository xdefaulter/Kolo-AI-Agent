#include <android/log.h>
#include <jni.h>

#include <algorithm>
#include <functional>
#include <mutex>
#include <sstream>
#include <string>
#include <vector>

#include "common.h"
#include "llama.h"
#include "sampling.h"

#define LOG_TAG "KoloLlamaBridge"

namespace {

constexpr int BATCH_SIZE = 64;
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
    std::mutex mutex;
    llama_tokens cached_tokens;
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

        const int64_t decode_start_us = llama_time_us();
        if (llama_decode(context, batch) != 0) {
            return 2;
        }
        __android_log_print(
                ANDROID_LOG_INFO,
                LOG_TAG,
                "completion_prompt_decode_chunk_done: offset=%d tokens=%d elapsed_ms=%.2f",
                i,
                cur_batch_size,
                static_cast<double>(llama_time_us() - decode_start_us) / 1000.0);
    }
    return 0;
}

bool is_valid_utf8(const std::string & value) {
    int expected = 0;
    for (unsigned char c : value) {
        if (expected == 0) {
            if ((c >> 7) == 0) continue;
            if ((c >> 5) == 0x6) expected = 1;
            else if ((c >> 4) == 0xE) expected = 2;
            else if ((c >> 3) == 0x1E) expected = 3;
            else return false;
        } else {
            if ((c >> 6) != 0x2) return false;
            expected--;
        }
    }
    return expected == 0;
}

int common_prefix_length(const llama_tokens & a, const llama_tokens & b) {
    const int count = std::min(static_cast<int>(a.size()), static_cast<int>(b.size()));
    int i = 0;
    while (i < count && a[i] == b[i]) {
        ++i;
    }
    return i;
}

std::string run_completion(
        KoloLlamaState * state,
        const std::string & prompt,
        jint max_tokens,
        jfloat temperature,
        jfloat top_p,
        jfloat repeat_penalty,
        const std::function<bool(const std::string &)> & on_token) {
    if (state == nullptr || state->model == nullptr || state->context == nullptr) {
        return "Local llama.cpp model is not loaded.";
    }

    if (prompt.empty()) {
        return "";
    }

    std::lock_guard<std::mutex> lock(state->mutex);

    __android_log_print(
            ANDROID_LOG_INFO,
            LOG_TAG,
            "completion_start: prompt_chars=%zu max_tokens=%d temp=%.3f top_p=%.3f repeat_penalty=%.3f",
            prompt.size(),
            static_cast<int>(max_tokens),
            static_cast<double>(temperature),
            static_cast<double>(top_p),
            static_cast<double>(repeat_penalty));

    llama_tokens prompt_tokens = common_tokenize(state->context, prompt, true, true);
    if (prompt_tokens.empty()) {
        return "";
    }

    __android_log_print(
            ANDROID_LOG_INFO,
            LOG_TAG,
            "completion_tokenized: prompt_tokens=%zu n_ctx=%d",
            prompt_tokens.size(),
            state->n_ctx);

    const int max_prompt_tokens = state->n_ctx - CONTEXT_HEADROOM - 1;
    if (static_cast<int>(prompt_tokens.size()) > max_prompt_tokens) {
        prompt_tokens.erase(
                prompt_tokens.begin(),
                prompt_tokens.end() - max_prompt_tokens);
        llama_memory_clear(llama_get_memory(state->context), false);
        state->cached_tokens.clear();
        __android_log_print(
                ANDROID_LOG_WARN,
                LOG_TAG,
                "completion_prompt_truncated: prompt_tokens=%zu max_prompt_tokens=%d",
                prompt_tokens.size(),
                max_prompt_tokens);
    }

    llama_memory_t memory = llama_get_memory(state->context);
    const int cached_tokens_before = static_cast<int>(state->cached_tokens.size());
    int cache_prefix_tokens = common_prefix_length(state->cached_tokens, prompt_tokens);
    if (cache_prefix_tokens == 0) {
        llama_memory_clear(memory, false);
        state->cached_tokens.clear();
    } else {
        if (cache_prefix_tokens == static_cast<int>(prompt_tokens.size())) {
            cache_prefix_tokens = std::max(0, cache_prefix_tokens - 1);
        }
        if (cache_prefix_tokens < static_cast<int>(state->cached_tokens.size())) {
            if (!llama_memory_seq_rm(memory, 0, cache_prefix_tokens, -1)) {
                llama_memory_clear(memory, false);
                state->cached_tokens.clear();
                cache_prefix_tokens = 0;
            } else {
                state->cached_tokens.resize(cache_prefix_tokens);
            }
        }
    }

    llama_tokens prompt_suffix(
            prompt_tokens.begin() + cache_prefix_tokens,
            prompt_tokens.end());

    __android_log_print(
            ANDROID_LOG_INFO,
            LOG_TAG,
            "completion_prompt_cache: hit_tokens=%d decode_tokens=%zu cached_tokens=%zu",
            cache_prefix_tokens,
            prompt_suffix.size(),
            state->cached_tokens.size());
    __android_log_print(
            ANDROID_LOG_INFO,
            LOG_TAG,
            "completion_prompt_cache_detail: previous_cached_tokens=%d prompt_tokens=%zu",
            cached_tokens_before,
            prompt_tokens.size());

    __android_log_print(
            ANDROID_LOG_INFO,
            LOG_TAG,
            "completion_prompt_decode_start: prompt_tokens=%zu",
            prompt_suffix.size());
    const int decode_result = decode_tokens(
            state->context,
            state->batch,
            prompt_suffix,
            cache_prefix_tokens,
            state->n_ctx);
    if (decode_result != 0) {
        return "llama.cpp prompt decode failed: " + std::to_string(decode_result);
    }
    state->cached_tokens = prompt_tokens;
    __android_log_write(ANDROID_LOG_INFO, LOG_TAG, "completion_prompt_decode_done");

    common_params_sampling sampling_params;
    sampling_params.temp = temperature;
    sampling_params.top_p = top_p;
    sampling_params.penalty_repeat = repeat_penalty;
    common_sampler * sampler = common_sampler_init(state->model, sampling_params);
    if (sampler == nullptr) {
        return "Failed to initialize llama.cpp sampler.";
    }

    std::string pending_utf8;
    llama_pos current_pos = static_cast<llama_pos>(prompt_tokens.size());
    const int n_predict = std::max(1, static_cast<int>(max_tokens));
    __android_log_print(
            ANDROID_LOG_INFO,
            LOG_TAG,
            "completion_generate_start: n_predict=%d current_pos=%d",
            n_predict,
            static_cast<int>(current_pos));

    for (int i = 0; i < n_predict; ++i) {
        if (current_pos >= state->n_ctx - CONTEXT_HEADROOM) {
            break;
        }

        const llama_token token = common_sampler_sample(sampler, state->context, -1);
        common_sampler_accept(sampler, token, true);

        if (llama_vocab_is_eog(llama_model_get_vocab(state->model), token)) {
            break;
        }

        pending_utf8 += common_token_to_piece(state->context, token);
        bool keep_going = true;
        bool emit_piece = false;
        if (is_valid_utf8(pending_utf8)) {
            if (i == 0) {
                __android_log_write(ANDROID_LOG_INFO, LOG_TAG, "completion_first_token");
            } else if ((i + 1) % 16 == 0) {
                __android_log_print(
                        ANDROID_LOG_INFO,
                        LOG_TAG,
                        "completion_generated_tokens=%d",
                        i + 1);
            }
            keep_going = on_token(pending_utf8);
            emit_piece = true;
        }

        common_batch_clear(state->batch);
        common_batch_add(state->batch, token, current_pos, {0}, true);
        const int64_t token_decode_start_us = llama_time_us();
        if (llama_decode(state->context, state->batch) != 0) {
            break;
        }
        state->cached_tokens.push_back(token);
        if ((i + 1) % 8 == 0) {
            __android_log_print(
                    ANDROID_LOG_INFO,
                    LOG_TAG,
                    "completion_token_decode_elapsed_ms=%.2f",
                    static_cast<double>(llama_time_us() - token_decode_start_us) / 1000.0);
        }
        current_pos++;
        if (emit_piece) {
            pending_utf8.clear();
        }
        if (!keep_going) {
            break;
        }
    }

    if (!pending_utf8.empty()) {
        on_token(pending_utf8);
    }

    common_sampler_free(sampler);
    __android_log_print(
            ANDROID_LOG_INFO,
            LOG_TAG,
            "completion_cache_committed: cached_tokens=%zu",
            state->cached_tokens.size());
    __android_log_write(ANDROID_LOG_INFO, LOG_TAG, "completion_done");
    return "";
}

}

extern "C" JNIEXPORT jboolean JNICALL
Java_com_kolo_agent_core_providers_local_LlamaCppBridge_nativeRuntimeAvailable(
        JNIEnv *,
        jobject) {
    init_backend_once();
    __android_log_print(
            ANDROID_LOG_INFO,
            LOG_TAG,
            "llama.cpp gpu_offload_supported=%s",
            llama_supports_gpu_offload() ? "true" : "false");
    return JNI_TRUE;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_kolo_agent_core_providers_local_LlamaCppBridge_nativeLoadModel(
        JNIEnv * env,
        jobject,
        jstring jmodel_path,
        jint context_size,
        jint threads,
        jint gpu_layers) {
    init_backend_once();

    const std::string model_path = get_jstring(env, jmodel_path);
    llama_model_params model_params = llama_model_default_params();
    model_params.n_gpu_layers = std::max(0, static_cast<int>(gpu_layers));
    if (model_params.n_gpu_layers == 0) {
        model_params.split_mode = LLAMA_SPLIT_MODE_NONE;
        model_params.main_gpu = -1;
    } else {
        model_params.split_mode = LLAMA_SPLIT_MODE_LAYER;
    }
    __android_log_print(
            ANDROID_LOG_INFO,
            LOG_TAG,
            "load_model_start: gpu_offload_supported=%s requested_gpu_layers=%d",
            llama_supports_gpu_offload() ? "true" : "false",
            model_params.n_gpu_layers);
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
    ctx_params.offload_kqv = model_params.n_gpu_layers > 0;
    ctx_params.op_offload = model_params.n_gpu_layers > 0;

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
    __android_log_print(
            ANDROID_LOG_INFO,
            LOG_TAG,
            "load_model_done: requested_gpu_layers=%d",
            model_params.n_gpu_layers);
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
    const std::string prompt = get_jstring(env, jprompt);
    std::ostringstream output;
    const std::string error = run_completion(
            state,
            prompt,
            max_tokens,
            temperature,
            top_p,
            repeat_penalty,
            [&output](const std::string & token) {
                output << token;
                return true;
            });
    if (!error.empty()) {
        return env->NewStringUTF(error.c_str());
    }
    const std::string result = output.str();
    return env->NewStringUTF(result.c_str());
}

extern "C" JNIEXPORT jstring JNICALL
Java_com_kolo_agent_core_providers_local_LlamaCppBridge_nativeCompleteStream(
        JNIEnv * env,
        jobject,
        jlong handle,
        jstring jprompt,
        jint max_tokens,
        jfloat temperature,
        jfloat top_p,
        jfloat repeat_penalty,
        jobject callback) {
    auto * state = reinterpret_cast<KoloLlamaState *>(handle);
    const std::string prompt = get_jstring(env, jprompt);

    if (callback == nullptr) {
        return env->NewStringUTF("Missing token callback.");
    }

    jclass callback_class = env->GetObjectClass(callback);
    jmethodID on_token = env->GetMethodID(callback_class, "onToken", "(Ljava/lang/String;)Z");
    if (on_token == nullptr) {
        return env->NewStringUTF("Invalid token callback.");
    }

    const std::string error = run_completion(
            state,
            prompt,
            max_tokens,
            temperature,
            top_p,
            repeat_penalty,
            [env, callback, on_token](const std::string & token) {
                jstring jtoken = env->NewStringUTF(token.c_str());
                const jboolean keep_going = env->CallBooleanMethod(callback, on_token, jtoken);
                env->DeleteLocalRef(jtoken);
                if (env->ExceptionCheck()) {
                    env->ExceptionClear();
                    return false;
                }
                return keep_going == JNI_TRUE;
            });

    return env->NewStringUTF(error.c_str());
}
