<script setup>
import { ref, computed, onMounted, onBeforeUnmount } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n, I18nT } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import Icon from 'next/icon/Icon.vue';
import NextButton from 'next/button/Button.vue';
import LoadingState from 'dashboard/components/widgets/LoadingState.vue';
import { parseAPIErrorResponse } from 'dashboard/store/utils/api';
import globalConstants from 'dashboard/constants/globals.js';
import {
  setupFacebookSdk,
  initWhatsAppEmbeddedSignup,
  createMessageHandler,
  isValidBusinessData,
} from './whatsapp/utils';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

// State
const fbSdkLoaded = ref(false);
const isProcessing = ref(false);
const processingMessage = ref('');
const authCodeReceived = ref(false);
const authCode = ref(null);
const businessData = ref(null);
const isAuthenticating = ref(false);

const benefits = computed(() => [
  {
    key: 'EASY_SETUP',
    text: t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BENEFITS.EASY_SETUP'),
  },
  {
    key: 'SECURE_AUTH',
    text: t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BENEFITS.SECURE_AUTH'),
  },
  {
    key: 'AUTO_CONFIG',
    text: t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.BENEFITS.AUTO_CONFIG'),
  },
]);

const showLoader = computed(() => isAuthenticating.value || isProcessing.value);

// Error handling
const handleSignupError = data => {
  isProcessing.value = false;
  authCodeReceived.value = false;
  isAuthenticating.value = false;

  const errorMessage =
    data.error ||
    data.message ||
    t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE');
  useAlert(errorMessage);
};

const handleSignupCancellation = () => {
  isProcessing.value = false;
  authCodeReceived.value = false;
  isAuthenticating.value = false;
};

const handleSignupSuccess = inboxData => {
  isProcessing.value = false;
  isAuthenticating.value = false;

  if (inboxData && inboxData.id) {
    useAlert(t('INBOX_MGMT.FINISH.MESSAGE'));
    router.replace({
      name: 'settings_inboxes_add_agents',
      params: {
        page: 'new',
        inbox_id: inboxData.id,
      },
    });
  } else {
    useAlert(t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.SUCCESS_FALLBACK'));
    router.replace({
      name: 'settings_inbox_list',
    });
  }
};

// Signup flow
const completeSignupFlow = async businessDataParam => {
  if (!authCodeReceived.value || !authCode.value) {
    handleSignupError({
      error: t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.AUTH_NOT_COMPLETED'),
    });
    return;
  }

  isProcessing.value = true;
  processingMessage.value = t(
    'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.PROCESSING'
  );

  try {
    const params = {
      code: authCode.value,
      business_id: businessDataParam.business_id,
      waba_id: businessDataParam.waba_id,
      phone_number_id: businessDataParam?.phone_number_id || '',
    };

    const responseData = await store.dispatch(
      'inboxes/createWhatsAppEmbeddedSignup',
      params
    );

    authCode.value = null;
    handleSignupSuccess(responseData);
  } catch (error) {
    const errorMessage =
      parseAPIErrorResponse(error) ||
      t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE');
    handleSignupError({ error: errorMessage });
  }
};

// Message handling
const handleEmbeddedSignupData = async data => {
  if (
    data.event === 'FINISH' ||
    data.event === 'FINISH_WHATSAPP_BUSINESS_APP_ONBOARDING'
  ) {
    const businessDataLocal = data.data;

    if (isValidBusinessData(businessDataLocal)) {
      businessData.value = businessDataLocal;
      if (authCodeReceived.value && authCode.value) {
        await completeSignupFlow(businessDataLocal);
      } else {
        processingMessage.value = t(
          'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.WAITING_FOR_AUTH'
        );
      }
    } else {
      handleSignupError({
        error: t(
          'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.INVALID_BUSINESS_DATA'
        ),
      });
    }
  } else if (data.event === 'CANCEL') {
    handleSignupCancellation();
  } else if (data.event === 'error') {
    handleSignupError({
      error:
        data.error_message ||
        t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.SIGNUP_ERROR'),
      error_id: data.error_id,
      session_id: data.session_id,
    });
  }
};

const handleSignupMessage = createMessageHandler(handleEmbeddedSignupData);

const requestWhatsAppViaGateway = async (authUrl) => {
  const width = 800;
  const height = 750;
  const left = window.screenX + (window.outerWidth - width) / 2;
  const top = window.screenY + (window.outerHeight - height) / 2;

  const popup = window.open(
    authUrl,
    'whatsapp_auth',
    `width=${width},height=${height},left=${left},top=${top}`
  );

  return new Promise((resolve, reject) => {
    const handleGatewayMessage = (event) => {
      if (!event.data || event.data.type !== 'whatsapp_embedded_auth') return;
      window.removeEventListener('message', handleGatewayMessage);
      popup.close();

      const { code, data } = event.data;
      if (code && data) {
        resolve({ code, data });
      } else {
        reject(new Error('Auth failed via gateway'));
      }
    };
    window.addEventListener('message', handleGatewayMessage);
  });
};

const launchEmbeddedSignup = async () => {
  try {
    isAuthenticating.value = true;
    processingMessage.value = t(
      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.AUTH_PROCESSING'
    );

    const gatewayUrl = window.chatwootConfig?.channelxGatewayUrl;

    if (gatewayUrl) {
      // Gateway popup flow
      const configId = window.chatwootConfig?.whatsappConfigurationId || '';
      const sourceServer = encodeURIComponent(window.location.origin);
      const authUrl = `${gatewayUrl}/whatsapp_signup?source_server=${sourceServer}&config_id=${configId}`;

      const { code, data } = await requestWhatsAppViaGateway(authUrl);
      authCode.value = code;
      authCodeReceived.value = true;
      businessData.value = data;
      completeSignupFlow(businessData.value);
      return;
    }

    // Original JS SDK popup flow (fallback)
    await setupFacebookSdk(
      window.channelxConfig?.whatsappAppId,
      window.channelxConfig?.whatsappApiVersion
    );
    fbSdkLoaded.value = true;

    const code = await initWhatsAppEmbeddedSignup(
      window.channelxConfig?.whatsappConfigurationId
    );

    authCode.value = code;
    authCodeReceived.value = true;
    processingMessage.value = t(
      'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.WAITING_FOR_BUSINESS_INFO'
    );

    if (businessData.value) {
      completeSignupFlow(businessData.value);
    }
  } catch (error) {
    if (error.message === 'Login cancelled') {
      isProcessing.value = false;
      isAuthenticating.value = false;
      useAlert(t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.CANCELLED'));
    } else {
      handleSignupError({
        error:
          error.message ||
          t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.SDK_LOAD_ERROR'),
      });
    }
  }
};

// Lifecycle
const setupMessageListener = () => {
  window.addEventListener('message', handleSignupMessage);
};

const cleanupMessageListener = () => {
  window.removeEventListener('message', handleSignupMessage);
};

const initialize = () => {
  setupMessageListener();
};

onMounted(() => {
  initialize();
});

onBeforeUnmount(() => {
  cleanupMessageListener();
});
</script>

<template>
  <div class="h-full">
    <LoadingState v-if="showLoader" :message="processingMessage" />

    <div v-else>
      <div class="flex flex-col items-start mb-6 text-start">
        <div class="flex justify-start mb-6">
          <div
            class="flex size-11 items-center justify-center rounded-full bg-n-alpha-2"
          >
            <Icon icon="i-woot-whatsapp" class="text-n-slate-10 size-6" />
          </div>
        </div>

        <h3 class="mb-2 text-base font-medium text-n-slate-12">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.TITLE') }}
        </h3>
        <p class="text-sm leading-[24px] text-n-slate-12">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.DESC') }}
        </p>
      </div>

      <div class="flex flex-col gap-2 mb-6">
        <div
          v-for="benefit in benefits"
          :key="benefit.key"
          class="flex gap-2 items-center text-sm text-n-slate-11"
        >
          <Icon icon="i-lucide-check" class="text-n-slate-11 size-4" />
          {{ benefit.text }}
        </div>
      </div>

      <div class="flex flex-col gap-2 mb-6">
        <I18nT
          keypath="INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.LEARN_MORE.TEXT"
          tag="span"
          class="text-sm text-n-slate-11"
        >
          <template #link>
            <a
              :href="globalConstants.WHATSAPP_EMBEDDED_SIGNUP_DOCS_URL"
              target="_blank"
              rel="noopener noreferrer"
              class="underline text-n-brand"
            >
              {{
                $t(
                  'INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.LEARN_MORE.LINK_TEXT'
                )
              }}
            </a>
          </template>
        </I18nT>
      </div>

      <div class="flex mt-4">
        <NextButton
          :disabled="isAuthenticating"
          :is-loading="isAuthenticating"
          faded
          slate
          class="w-full"
          @click="launchEmbeddedSignup"
        >
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.EMBEDDED_SIGNUP.SUBMIT_BUTTON') }}
        </NextButton>
      </div>
    </div>
  </div>
</template>
