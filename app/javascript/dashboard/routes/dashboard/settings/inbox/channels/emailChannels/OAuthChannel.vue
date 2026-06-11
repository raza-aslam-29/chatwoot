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

const GATEWAY_URL = window.channelxConfig?.channelxGatewayUrl || '';

const client = computed(() => {
  if (props.provider === 'microsoft') {
    return microsoftClient;
  }
  return googleClient;
});

async function requestAuthorization() {
  try {
    isRequestingAuthorization.value = true;
    const response = await client.value.generateAuthorization();
    const {
      data: { url },
    } = response;

    window.location.href = url;
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
