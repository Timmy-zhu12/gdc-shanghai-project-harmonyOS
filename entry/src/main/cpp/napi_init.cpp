#include "napi/native_api.h"

#include <string>

static napi_value IsBackendAvailable(napi_env env, napi_callback_info info)
{
    napi_value result;
    napi_get_boolean(env, false, &result);
    return result;
}

static napi_value Infer(napi_env env, napi_callback_info info)
{
    napi_value result;
    std::string message;
    napi_create_string_utf8(env, message.c_str(), message.length(), &result);
    return result;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"isBackendAvailable", nullptr, IsBackendAvailable, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"infer", nullptr, Infer, nullptr, nullptr, nullptr, napi_default, nullptr}
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module cardioGemma4Module = {
    1,
    0,
    nullptr,
    Init,
    "cardio_gemma4",
    nullptr,
    {0},
};

extern "C" __attribute__((constructor)) void RegisterCardioGemma4Module(void)
{
    napi_module_register(&cardioGemma4Module);
}
