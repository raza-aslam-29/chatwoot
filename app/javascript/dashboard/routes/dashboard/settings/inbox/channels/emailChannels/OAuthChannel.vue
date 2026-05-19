<script setup>
import { ref, computed } from 'vue';

import microsoftClient from 'dashboard/api/channel/microsoftClient';
import googleClient from 'dashboard/api/channel/googleClient';
import SettingsSubPageHeader from '../../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import LoadingState from 'dashboard/components/widgets/LoadingState.vue';

import { useAlert } from 'dashboard/composables';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  provider: {
    type: String,
    required: true,
    validate: value => ['microsoft', 'google'].includes(value),
  },
  title: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    required: true,
  },
  submitButtonText: {
    type: String,
    required: true,
  },
  errorMessage: {
    type: String,
    required: true,
  },
});

const router = useRouter();
const { t } = useI18n();
const isRequestingAuthorization = ref(false);
const isProcessing = ref(false);

const showLoader = computed(() => isRequestingAuthorization.value || isProcessing.value);

const GATEWAY_URL = window.chatwootConfig?.channelxGatewayUrl || '';

const client = computed(() => {
  if (props.provider === 'microsoft') {
    return microsoftClient;
  }
  return googleClient;
});

// Gateway popup flow — shared between google and microsoft providers.
// The gateway posts back `{ type: '<provider>_auth', code, state }` after the OAuth redirect.
async function requestViaGateway(authUrl, provider) {
  const width = 700;
  const height = 700;
  const left = window.screenX + (window.outerWidth - width) / 2;
  const top = window.screenY + (window.outerHeight - height) / 2;

  const messageType = `${provider}_auth`;
  const tag = `[${provider} OAuth]`;

  console.log(`${tag} Opening popup to:`, authUrl);

  const popup = window.open(
    authUrl,
    messageType,
    `width=${width},height=${height},left=${left},top=${top}`
  );

  if (!popup) {
    console.error(`${tag} Popup was blocked by the browser!`);
  } else {
    console.log(`${tag} Popup opened successfully`);
  }

  console.log(`${tag} Listening for postMessage from gateway...`);

  return new Promise((resolve, reject) => {
    const handleMessage = async event => {
      console.log(`${tag} Received message event:`, event.origin, event.data);

      if (!event.data || event.data.type !== messageType) {
        console.log(`${tag} Ignoring message — type is not ${messageType}:`, event.data?.type);
        return;
      }

      console.log(`${tag} ✅ ${messageType} message received! Code present:`, !!event.data.code);
      window.removeEventListener('message', handleMessage);

      const { code, state } = event.data;
      if (!code) {
        console.error(`${tag} ❌ No code in ${messageType} message`);
        reject(new Error('No auth code received from gateway'));
        return;
      }

      try {
        isRequestingAuthorization.value = false;
        isProcessing.value = true;
        console.log(`${tag} Calling /finalize with code (first 20 chars):`, code.substring(0, 20));
        const response = await client.value.finalizeCallback({ code, state });
        console.log(`${tag} ✅ Finalize response:`, response.data);
        resolve(response.data);
      } catch (err) {
        console.error(`${tag} ❌ Finalize API error:`, err?.response?.data || err.message);
        reject(err);
      }
    };
    window.addEventListener('message', handleMessage);
  });
}

async function requestAuthorization() {
  try {
    isRequestingAuthorization.value = true;
    const response = await client.value.generateAuthorization();
    const {
      data: { url },
    } = response;

    // Gateway configured → popup flow (works for both google and microsoft)
    if (GATEWAY_URL) {
      const result = await requestViaGateway(url, props.provider);
      isProcessing.value = false;
      useAlert(t('INBOX_MGMT.FINISH.MESSAGE'));
      router.replace({
        name: result.already_exists
          ? 'app_email_inbox_settings'
          : 'settings_inboxes_add_agents',
        params: result.already_exists
          ? { inbox_id: result.inbox_id }
          : { page: 'new', inbox_id: result.inbox_id },
      });
    } else {
      // No gateway → original redirect flow
      window.location.href = url;
    }
  } catch (error) {
    isProcessing.value = false;
    useAlert(props.errorMessage);
  } finally {
    isRequestingAuthorization.value = false;
  }
}
</script>

<template>
  <div class="h-full w-full p-6 col-span-6">
    <SettingsSubPageHeader
      :header-title="title"
      :header-content="description"
    />
    <LoadingState v-if="showLoader" />
    <form v-else class="mt-6" @submit.prevent="requestAuthorization">
      <NextButton
        :is-loading="isRequestingAuthorization"
        type="submit"
        solid
        blue
        :label="submitButtonText"
      />
    </form>
  </div>
</template>
