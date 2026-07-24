<script>
/* eslint-env browser */
/* global FB */
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { required } from '@vuelidate/validators';
import LoadingState from 'dashboard/components/widgets/LoadingState.vue';

import { useI18n } from 'vue-i18n';
import ChannelApi from '../../../../../api/channels';
import PageHeader from '../../SettingsSubPageHeader.vue';
import router from '../../../../index';
import { useBranding } from 'shared/composables/useBranding';
import NextButton from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

import { loadScript } from 'dashboard/helper/DOMHelpers';
import * as Sentry from '@sentry/vue';

export default {
  components: {
    LoadingState,
    PageHeader,
    NextButton,
    ComboBox,
  },
  setup() {
    const { replaceInstallationName } = useBranding();
    const { t } = useI18n();
    const { accountId } = useAccount();
    return {
      accountId,
      replaceInstallationName,
      t,
      v$: useVuelidate(),
    };
  },
  data() {
    return {
      isFetching: false,
      isProcessing: false,
      userAccessToken: '',
      isCreating: false,
      hasError: false,
      omniauth_token: '',
      channel: 'facebook',
      selectedPage: { name: null, id: null },
      pageName: '',
      pageList: [],
      emptyStateMessage: this.$t('INBOX_MGMT.DETAILS.LOADING_FB'),
      errorStateMessage: '',
      errorStateDescription: '',
      hasLoginStarted: false,
    };
  },

  validations: {
    pageName: {
      required,
    },

    selectedPage: {
      isEmpty() {
        return this.selectedPage !== null && !!this.selectedPage.name;
      },
    },
  },

  computed: {
    showLoader() {
      return this.isFetching || this.isProcessing || this.isCreating;
    },
    getSelectablePages() {
      return this.pageList.filter(item => !item.exists);
    },
    comboBoxPageOptions() {
      return this.getSelectablePages.map(({ id, name }) => ({
        value: id,
        label: name,
      }));
    },
    emptyState() {
      return this.pageList.length === 0;
    },
  },

  mounted() {
    window.fbAsyncInit = this.runFBInit;

    // Handle redirect back from gateway-based Facebook OAuth flow
    const urlParams = new URLSearchParams(window.location.search);
    const errorType = urlParams.get('error_type');
    const errorMessage = urlParams.get('error_message');

    // Clean up query params from URL immediately
    window.history.replaceState({}, document.title, window.location.pathname);

    if (errorMessage || errorType) {
      this.hasLoginStarted = true;
      this.hasError = true;
      this.errorStateMessage = errorMessage || this.$t('INBOX_MGMT.DETAILS.ERROR_FB_AUTH');
      return;
    }
  },

  methods: {
    async requestFacebookViaGateway(authUrl) {
      const width = 700;
      const height = 700;
      const left = window.screenX + (window.outerWidth - width) / 2;
      const top = window.screenY + (window.outerHeight - height) / 2;

      const popup = window.open(
        authUrl,
        'facebook_auth',
        `width=${width},height=${height},left=${left},top=${top}`
      );

      return new Promise((resolve, reject) => {
        const handleMessage = event => {
          if (!event.data || event.data.type !== 'facebook_auth') return;

          window.removeEventListener('message', handleMessage);
          popup.close();

          // The gateway already exchanged the code for a long-lived user access
          // token server-side (using its own Meta app credentials), so this
          // instance never needs FB_APP_ID/FB_APP_SECRET. Consume the token directly.
          const { user_access_token: userAccessToken } = event.data;
          if (!userAccessToken) {
            reject(new Error('No access token received'));
            return;
          }
          resolve(userAccessToken);
        };
        window.addEventListener('message', handleMessage);
      });
    },

    async startLogin() {
      this.hasLoginStarted = true;
      const gatewayUrl = window.channelxConfig?.channelxGatewayUrl;
      if (gatewayUrl) {
        // Gateway configured → popup flow
        const loginUrl = `${gatewayUrl}/facebook/login?source_server=${encodeURIComponent(window.location.origin)}&account_id=${this.accountId}`;
        try {
          const userAccessToken = await this.requestFacebookViaGateway(loginUrl);
          this.userAccessToken = userAccessToken;
          this.fetchPages(userAccessToken);
        } catch (error) {
          useAlert(this.t('INBOX_MGMT.ADD.FB.ERROR_MESSAGE'));
          this.hasLoginStarted = false;
        }
        return;
      }

      // No gateway → fallback to FB JS SDK popup (self-hosted installs)
      try {
        await this.loadFBsdk();
        this.runFBInit();
        this.tryFBlogin();
      } catch (error) {
        if (error.name === 'ScriptLoaderError') {
          useAlert(this.$t('INBOX_MGMT.DETAILS.ERROR_FB_LOADING'));
        } else {
          Sentry.captureException(error);
          useAlert(this.$t('INBOX_MGMT.DETAILS.ERROR_FB_AUTH'));
        }
      }
    },

    setPageName(pageId) {
      const page = this.pageList.find(p => p.id === pageId);
      if (page) {
        this.selectedPage = page;
        this.pageName = page.name;
      } else {
        this.selectedPage = { name: null, id: null };
        this.pageName = '';
      }
      this.v$.selectedPage.$touch();
    },

    initChannelAuth(channel) {
      if (channel === 'facebook') {
        this.loadFBsdk();
      }
    },

    runFBInit() {
      FB.init({
        appId: window.channelxConfig.fbAppId,
        xfbml: true,
        version: window.channelxConfig.fbApiVersion,
        status: true,
      });
      window.fbSDKLoaded = true;
      FB.AppEvents.logPageView();
    },

    async loadFBsdk() {
      return loadScript('https://connect.facebook.net/en_US/sdk.js', {
        id: 'facebook-jssdk',
      });
    },

    tryFBlogin() {
      FB.login(
        response => {
          this.hasError = false;
          if (response.status === 'connected') {
            this.fetchPages(response.authResponse.accessToken);
          } else if (response.status === 'not_authorized') {
            console.error('FACEBOOK AUTH ERROR', response);
            this.hasError = true;
            this.errorStateMessage = this.$t(
              'INBOX_MGMT.DETAILS.ERROR_FB_UNAUTHORIZED'
            );
            this.errorStateDescription = this.$t(
              'INBOX_MGMT.DETAILS.ERROR_FB_UNAUTHORIZED_HELP'
            );
          } else {
            console.error('FACEBOOK AUTH ERROR', response);
            this.hasError = true;
            this.errorStateMessage = this.$t(
              'INBOX_MGMT.DETAILS.ERROR_FB_AUTH'
            );
            this.errorStateDescription = '';
          }
        },
        {
          scope:
            'pages_manage_metadata,business_management,pages_messaging,pages_show_list',
        }
      );
    },

    async fetchPages(_token) {
      this.isFetching = true;
      try {
        const response = await ChannelApi.fetchFacebookPages(
          _token,
          this.accountId
        );
        const {
          data: { data },
        } = response;
        this.pageList = data.page_details;
        this.userAccessToken = data.user_access_token;
      } catch (error) {
        // Ignore error
      } finally {
        this.isFetching = false;
      }
    },

    channelParams() {
      return {
        user_access_token: this.userAccessToken,
        page_access_token: this.selectedPage.access_token,
        page_id: this.selectedPage.id,
        inbox_name: this.selectedPage.name?.trim(),
      };
    },

    createChannel() {
      this.v$.$touch();
      if (!this.v$.$error) {
        this.emptyStateMessage = this.$t('INBOX_MGMT.DETAILS.CREATING_CHANNEL');
        this.isCreating = true;
        this.$store
          .dispatch('inboxes/createFBChannel', this.channelParams())
          .then(data => {
            router.replace({
              name: 'settings_inboxes_add_agents',
              params: { page: 'new', inbox_id: data.id },
            });
          })
          .catch(() => {
            this.isCreating = false;
          });
      }
    },
  },
};
</script>

<template>
  <div class="w-full h-full col-span-6 p-6 overflow-auto">
    <div
      v-if="!hasLoginStarted"
      class="flex flex-col items-center justify-center h-full text-center"
    >
      <a href="#" @click.prevent="startLogin()">
        <img
          class="w-auto h-10 rounded-md"
          src="~dashboard/assets/images/channels/facebook_login.png"
          alt="Facebook-logo"
        />
      </a>
      <p class="py-6">
        {{ replaceInstallationName($t('INBOX_MGMT.ADD.FB.HELP')) }}
      </p>
    </div>
    <div v-else>
      <div v-if="hasError" class="max-w-lg mx-auto text-center">
        <h5>{{ errorStateMessage }}</h5>
        <p
          v-if="errorStateDescription"
          v-dompurify-html="errorStateDescription"
        />
      </div>
      <LoadingState v-else-if="showLoader" :message="emptyStateMessage" />
      <form
        v-else
        class="flex flex-col flex-wrap mx-0"
        @submit.prevent="createChannel()"
      >
        <div class="w-full">
          <PageHeader
            :header-title="$t('INBOX_MGMT.ADD.DETAILS.TITLE')"
            :header-content="
              replaceInstallationName($t('INBOX_MGMT.ADD.DETAILS.DESC'))
            "
          />
        </div>
        <div class="w-3/5">
          <div class="w-full mb-2">
            <div class="input-wrap" :class="{ error: v$.selectedPage.$error }">
              <span class="text-n-slate-12 text-start">
                {{ $t('INBOX_MGMT.ADD.FB.CHOOSE_PAGE') }}
              </span>
              <ComboBox
                :model-value="selectedPage.id"
                :options="comboBoxPageOptions"
                :placeholder="$t('INBOX_MGMT.ADD.FB.PICK_A_VALUE')"
                :has-error="v$.selectedPage.$error"
                class="[&>div>button]:!bg-n-alpha-black2 mt-1"
                @update:model-value="setPageName"
              />
              <span v-if="v$.selectedPage.$error" class="message mt-0.5">
                {{ $t('INBOX_MGMT.ADD.FB.CHOOSE_PLACEHOLDER') }}
              </span>
            </div>
          </div>
          <div class="w-full">
            <label :class="{ error: v$.pageName.$error }">
              {{ $t('INBOX_MGMT.ADD.FB.INBOX_NAME') }}
              <input
                v-model="pageName"
                type="text"
                :placeholder="$t('INBOX_MGMT.ADD.FB.PICK_NAME')"
                @input="v$.pageName.$touch"
              />
              <span v-if="v$.pageName.$error" class="message">
                {{ $t('INBOX_MGMT.ADD.FB.ADD_NAME') }}
              </span>
            </label>
          </div>
          <div class="w-full text-right">
            <NextButton :label="$t('INBOX_MGMT.ADD.FB.CREATE_INBOX')" />
          </div>
        </div>
      </form>
    </div>
  </div>
</template>
