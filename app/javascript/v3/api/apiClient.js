import axios from 'axios';

const { apiHost = '' } = window.channelxConfig || {};
const wootAPI = axios.create({ baseURL: `${apiHost}/` });

export default wootAPI;
