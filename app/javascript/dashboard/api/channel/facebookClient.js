/* global axios */
import ApiClient from '../ApiClient';

class FacebookClient extends ApiClient {
  constructor() {
    super('facebook', { accountScoped: true });
  }

  finalizeCallback(payload) {
    return axios.post(`${this.url}/finalize`, payload);
  }
}

export default new FacebookClient();
