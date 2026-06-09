/* global axios */
import ApiClient from '../ApiClient';

class MicrosoftClient extends ApiClient {
  constructor() {
    super('microsoft', { accountScoped: true });
  }

  generateAuthorization(payload = {}) {
    // Pass the real browser origin so the backend can embed it in the OAuth state.
    // This ensures postMessage targets the correct origin (not 0.0.0.0 from FRONTEND_URL).
    return axios.post(`${this.url}/authorization`, {
      ...payload,
      source_server: window.location.origin,
    });
  }

  finalizeCallback(payload) {
    return axios.post(`${this.url}/finalize`, payload);
  }
}

export default new MicrosoftClient();
