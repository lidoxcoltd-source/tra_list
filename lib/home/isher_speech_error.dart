const _retryableSpeechErrors = {
  'error_no_match',
  'error_speech_timeout',
  'error_busy',
  'error_network',
  'error_network_timeout',
  'error_server',
  'error_server_disconnected',
  'error_too_many_requests',
  'error_client',
};

bool isRetryableIsherSpeechError(String message) {
  final normalized = message.toLowerCase();
  return _retryableSpeechErrors.any(normalized.contains);
}
