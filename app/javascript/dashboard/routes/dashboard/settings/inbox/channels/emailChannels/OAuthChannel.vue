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

// Google: gateway popup flow
async function requestGoogleViaGateway(authUrl) {
  const width = 700;
  const height = 700;
  const left = window.screenX + (window.outerWidth - width) / 2;
  const top = window.screenY + (window.outerHeight - height) / 2;

  console.log('[Google OAuth] Opening popup to:', authUrl);

  const popup = window.open(
    authUrl,
    'google_auth',
    `width=${width},height=${height},left=${left},top=${top}`
  );

  if (!popup) {
    console.error('[Google OAuth] Popup was blocked by the browser!');
  } else {
    console.log('[Google OAuth] Popup opened successfully');
  }

  console.log('[Google OAuth] Listening for postMessage from gateway...');

  return new Promise((resolve, reject) => {
    const handleMessage = async event => {
      console.log('[Google OAuth] Received message event:', event.origin, event.data);

      if (!event.data || event.data.type !== 'google_auth') {
        console.log('[Google OAuth] Ignoring message — type is not google_auth:', event.data?.type);
        return;
      }

      console.log('[Google OAuth] ✅ google_auth message received! Code present:', !!event.data.code);
      window.removeEventListener('message', handleMessage);

      const { code, state } = event.data;
      if (!code) {
        console.error('[Google OAuth] ❌ No code in google_auth message');
        reject(new Error('No auth code received from gateway'));
        return;
      }

      try {
        isRequestingAuthorization.value = false;
        isProcessing.value = true;
        console.log('[Google OAuth] Calling /finalize with code (first 20 chars):', code.substring(0, 20));
        const response = await googleClient.finalizeCallback({ code, state });
        console.log('[Google OAuth] ✅ Finalize response:', response.data);
        resolve(response.data);
      } catch (err) {
        console.error('[Google OAuth] ❌ Finalize API error:', err?.response?.data || err.message);
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

    // Google + gateway configured → popup flow
    if (props.provider === 'google' && GATEWAY_URL) {
      const result = await requestGoogleViaGateway(url);
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
      // Microsoft or no gateway → original redirect flow
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
