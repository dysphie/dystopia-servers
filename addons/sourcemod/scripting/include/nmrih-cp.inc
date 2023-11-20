/** Double-include prevention */
#if defined _nmrihcp_included_
  #endinput
#endif
#define _nmrihcp_included_

forward Action OnChatMessage(int& author, ArrayList recipients, char[] authorName, char[] message);