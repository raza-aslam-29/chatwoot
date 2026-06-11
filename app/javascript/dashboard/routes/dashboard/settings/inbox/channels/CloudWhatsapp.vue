<script setup>
import { ref, computed } from 'vue';
import { useStore } from 'vuex';
import { useRouter } from 'vue-router';
import { useI18n } from 'vue-i18n';
import { useVuelidate } from '@vuelidate/core';
import { required } from '@vuelidate/validators';
import { useAlert } from 'dashboard/composables';
import { isPhoneE164OrEmpty, isNumber } from 'shared/helpers/Validators';
import LoadingState from 'dashboard/components/widgets/LoadingState.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

const store = useStore();
const router = useRouter();
const { t } = useI18n();

// ── Gateway detection ──────────────────────────────────────────────────────
const gatewayUrl = window.channelxConfig?.channelxGatewayUrl || '';
const useGateway = computed(() => !!gatewayUrl);

// ── Gateway flow state ─────────────────────────────────────────────────────
const isConnecting = ref(false);

// ── Manual form state ──────────────────────────────────────────────────────
const inboxName = ref('');
const phoneNumber = ref('');
const apiKey = ref('');
const phoneNumberId = ref('');
const businessAccountId = ref('');

const uiFlags = computed(() => store.getters['inboxes/getUIFlags']);

// Vuelidate only used in manual mode
const rules = computed(() =>
  useGateway.value
    ? {}
    : {
        inboxName: { required },
        phoneNumber: { required, isPhoneE164OrEmpty },
        apiKey: { required },
        phoneNumberId: { required, isNumber },
        businessAccountId: { required, isNumber },
      }
);

const v$ = useVuelidate(rules, {
  inboxName,
  phoneNumber,
  apiKey,
  phoneNumberId,
  businessAccountId,
});

// ── Shared channel creation ────────────────────────────────────────────────
async function createWhatsappChannel(payload) {
  const whatsappChannel = await store.dispatch('inboxes/createChannel', payload);
  router.replace({
    name: 'settings_inboxes_add_agents',
    params: { page: 'new', inbox_id: whatsappChannel.id },
  });
}

// ── Gateway flow ───────────────────────────────────────────────────────────
async function connectViaGateway() {
  isConnecting.value = true;
  try {
    const sourceServer = encodeURIComponent(window.location.origin);
    const authUrl = `${gatewayUrl}/whatsapp_manual?source_server=${sourceServer}`;

    const width = 800;
    const height = 750;
    const left = window.screenX + (window.outerWidth - width) / 2;
    const top = window.screenY + (window.outerHeight - height) / 2;

    const popup = window.open(
      authUrl,
      'whatsapp_manual_auth',
      `width=${width},height=${height},left=${left},top=${top}`
    );

    const result = await new Promise((resolve, reject) => {
      const handler = event => {
        if (!event.data || event.data.type !== 'whatsapp_manual_auth') return;
        window.removeEventListener('message', handler);
        popup?.close();

        const { api_key, phone_number, phone_number_id, business_account_id, inbox_name } =
          event.data;

        if (api_key && phone_number_id && business_account_id) {
          resolve({ api_key, phone_number, phone_number_id, business_account_id, inbox_name });
        } else {
          reject(new Error(t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE')));
        }
      };
      window.addEventListener('message', handler);
    });

    await createWhatsappChannel({
      name: result.inbox_name?.trim() || result.phone_number || result.phone_number_id,
      channel: {
        type: 'whatsapp',
        phone_number: result.phone_number,
        provider: 'whatsapp_cloud',
        provider_config: {
          api_key: result.api_key,
          phone_number_id: result.phone_number_id,
          business_account_id: result.business_account_id,
        },
      },
    });
  } catch (error) {
    useAlert(error.message || t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE'));
  } finally {
    isConnecting.value = false;
  }
}

// ── Manual form submit ─────────────────────────────────────────────────────
async function createChannelManually() {
  v$.value.$touch();
  if (v$.value.$invalid) return;

  try {
    await createWhatsappChannel({
      name: inboxName.value?.trim(),
      channel: {
        type: 'whatsapp',
        phone_number: phoneNumber.value,
        provider: 'whatsapp_cloud',
        provider_config: {
          api_key: apiKey.value,
          phone_number_id: phoneNumberId.value,
          business_account_id: businessAccountId.value,
        },
      },
    });
  } catch (error) {
    useAlert(error.message || t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE'));
  }
}
</script>

<template>
  <!-- ── Gateway mode ─────────────────────────────────────────────────────── -->
  <div v-if="useGateway">
    <LoadingState v-if="isConnecting" />
    <div v-else class="flex flex-col items-start">
      <p class="mb-4 text-sm text-n-slate-11">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.GATEWAY.DESCRIPTION') }}
      </p>
      <NextButton
        solid
        blue
        :label="$t('INBOX_MGMT.ADD.WHATSAPP.GATEWAY.BUTTON')"
        @click="connectViaGateway"
      />
    </div>
  </div>

  <!-- ── Manual form (no gateway) ─────────────────────────────────────────── -->
  <form v-else class="flex flex-wrap flex-col mx-0" @submit.prevent="createChannelManually">
    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.inboxName.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.LABEL') }}
        <input
          v-model="inboxName"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.PLACEHOLDER')"
          @blur="v$.inboxName.$touch"
        />
        <span v-if="v$.inboxName.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.ERROR') }}
        </span>
      </label>
    </div>

    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.phoneNumber.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.LABEL') }}
        <input
          v-model="phoneNumber"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.PLACEHOLDER')"
          @blur="v$.phoneNumber.$touch"
        />
        <span v-if="v$.phoneNumber.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.ERROR') }}
        </span>
      </label>
    </div>

    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.phoneNumberId.$error }">
        <span>
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER_ID.LABEL') }}
        </span>
        <input
          v-model="phoneNumberId"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER_ID.PLACEHOLDER')"
          @blur="v$.phoneNumberId.$touch"
        />
        <span v-if="v$.phoneNumberId.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER_ID.ERROR') }}
        </span>
      </label>
    </div>

    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.businessAccountId.$error }">
        <span>
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.BUSINESS_ACCOUNT_ID.LABEL') }}
        </span>
        <input
          v-model="businessAccountId"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.BUSINESS_ACCOUNT_ID.PLACEHOLDER')"
          @blur="v$.businessAccountId.$touch"
        />
        <span v-if="v$.businessAccountId.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.BUSINESS_ACCOUNT_ID.ERROR') }}
        </span>
      </label>
    </div>

    <div class="flex-shrink-0 flex-grow-0">
      <label :class="{ error: v$.apiKey.$error }">
        <span>
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.LABEL') }}
        </span>
        <input
          v-model="apiKey"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.PLACEHOLDER')"
          @blur="v$.apiKey.$touch"
        />
        <span v-if="v$.apiKey.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.API_KEY.ERROR') }}
        </span>
      </label>
    </div>

    <div class="w-full mt-4">
      <NextButton
        :is-loading="uiFlags.isCreating"
        type="submit"
        solid
        blue
        :label="$t('INBOX_MGMT.ADD.WHATSAPP.SUBMIT_BUTTON')"
      />
    </div>
  </form>
</template>
