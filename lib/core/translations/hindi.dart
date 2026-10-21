/// Hindi (Devanagari) text, keyed by the English text. Every key also needs
/// an entry in hinglish.dart (test/core/translations checks both).
const Map<String, String> hindi = <String, String>{
  // App shell
  'Home': 'होम',
  'Transactions': 'लेन-देन',
  'Khata': 'खाता',
  'Reports': 'रिपोर्ट',
  'Dashboard': 'डैशबोर्ड',
  'Add transaction': 'लेन-देन जोड़ें',
  'Add contact': 'संपर्क जोड़ें',
  'Open profile': 'प्रोफ़ाइल खोलें',
  'Switch account': 'अकाउंट बदलें',
  'Hello, @name': 'नमस्ते, @name',
  'Track your finances': 'अपने पैसों का हिसाब रखें',
  'Search transactions': 'लेन-देन खोजें',
  'User': 'उपयोगकर्ता',
  'Language': 'भाषा',

  // Dashboard
  '@error Pull down to retry.': '@error दोबारा कोशिश के लिए नीचे खींचें।',
  'Good morning': 'सुप्रभात',
  'Good afternoon': 'शुभ दोपहर',
  'Good evening': 'शुभ संध्या',
  'Monthly Pace': 'महीने की रफ़्तार',
  '@days days left': '@days दिन बाकी',
  '🟢 On track: @amount net saved this month':
      '🟢 सही दिशा में: इस महीने @amount की शुद्ध बचत',
  '⚠️ Spent @amount across the month': '⚠️ इस महीने @amount खर्च हुए',
  '💡 Day @day of @total: Track expenses daily to stay in control':
      '💡 @total में से दिन @day: नियंत्रण में रहने के लिए रोज़ खर्च लिखें',
  'Budgets →': 'बजट →',
  'This month': 'इस महीने',
  'Income': 'आमदनी',
  'Expense': 'खर्च',
  'Net': 'शुद्ध',
  'Transfers are not counted as income or expense.':
      'ट्रांसफ़र को आमदनी या खर्च में नहीं गिना जाता।',
  'Spending overview': 'खर्च का सारांश',
  'Details': 'विवरण',
  'Uncategorised': 'बिना श्रेणी',
  'Food': 'खाना',
  'Groceries': 'राशन',
  'Bills': 'बिल',
  'Shopping': 'खरीदारी',
  'No expenses recorded this month': 'इस महीने कोई खर्च दर्ज नहीं',
  'Keep track of where your money goes. As soon as you log expenses, your category breakdown and visual chart will show here.':
      'देखिए आपका पैसा कहाँ जाता है। खर्च दर्ज करते ही श्रेणीवार हिसाब और चार्ट यहाँ दिखेगा।',
  'Add your first expense': 'अपना पहला खर्च जोड़ें',
  'Tip: Daily tracking uncovers 15–20% in hidden monthly savings!':
      'सुझाव: रोज़ हिसाब रखने से हर महीने 15–20% छिपी बचत मिलती है!',
  'Plan ahead': 'आगे की योजना',
  'Budgets': 'बजट',
  'Set limits and track spend': 'सीमा तय करें और खर्च पर नज़र रखें',
  'Recurring': 'नियमित लेन-देन',
  'Rent, bills, EMIs on autopilot': 'किराया, बिल, EMI अपने आप',
  'Reminders': 'रिमाइंडर',
  'Never miss a due date': 'कोई तारीख न चूकें',
  'Notifications': 'सूचनाएँ',
  'Payment alerts received': 'मिले हुए भुगतान अलर्ट',
  'Add your first account': 'अपना पहला अकाउंट जोड़ें',
  'Create a cash, bank or UPI account with its opening balance. Then you can record income and expenses.':
      'शुरुआती बैलेंस के साथ कैश, बैंक या UPI अकाउंट बनाएँ। फिर आमदनी और खर्च दर्ज कर सकते हैं।',
  'Add account': 'अकाउंट जोड़ें',
  'Credit': 'उधार दिया',
  'Debit': 'उधार लिया',
  'Transfer': 'ट्रांसफ़र',
  'Today': 'आज',
  "Today's income": 'आज की आमदनी',
  "Today's expense": 'आज का खर्च',
  'Open': 'खोलें',
  'No contacts yet': 'अभी कोई संपर्क नहीं',
  'Track who owes you and who you owe. Add your first contact.':
      'किससे लेना है और किसे देना है, हिसाब रखें। अपना पहला संपर्क जोड़ें।',
  'Add': 'जोड़ें',
  'You will get': 'आपको मिलेंगे',
  'You will give': 'आपको देने हैं',
  'Accounts': 'अकाउंट',
  'Manage': 'प्रबंधित करें',
  'Recent transactions': 'हाल के लेन-देन',
  'See all': 'सभी देखें',
  'No transactions yet': 'अभी कोई लेन-देन नहीं',
  'Record your first income or expense to see it here.':
      'अपनी पहली आमदनी या खर्च दर्ज करें, वह यहाँ दिखेगा।',
  'Add expense': 'खर्च जोड़ें',

  // Dashboard quotes (translated where shown)
  'Do not save what is left after spending, but spend what is left after saving.':
      'खर्च के बाद जो बचे उसे न बचाएँ, बल्कि बचत के बाद जो बचे उसे खर्च करें।',
  'Beware of little expenses. A small leak will sink a great ship.':
      'छोटे खर्चों से सावधान रहें। एक छोटा छेद बड़े जहाज़ को डुबो देता है।',
  'A budget is telling your money where to go instead of wondering where it went.':
      'बजट का मतलब है पैसे को बताना कि कहाँ जाना है, न कि सोचना कि कहाँ गया।',
  'Financial freedom is available to those who learn about it and work for it.':
      'आर्थिक आज़ादी उन्हें मिलती है जो इसे सीखते हैं और इसके लिए मेहनत करते हैं।',
  'The secret of getting ahead is getting started. Track your daily expenses.':
      'आगे बढ़ने का राज़ है शुरुआत करना। रोज़ के खर्च लिखें।',
  'Small daily savings compound into monumental financial security.':
      'रोज़ की छोटी बचत मिलकर बड़ी आर्थिक सुरक्षा बनती है।',
  'Never spend your money before you have earned it.':
      'कमाने से पहले कभी पैसा खर्च न करें।',
  'The art is not in making money, but in keeping it.':
      'कला पैसा कमाने में नहीं, उसे बचाने में है।',
  'Financial Wisdom': 'आर्थिक सीख',
  'Proverb': 'कहावत',

  // Settings
  'Settings': 'सेटिंग्स',
  'Appearance': 'दिखावट',
  'Region and format': 'क्षेत्र और फ़ॉर्मैट',
  'Data & Backup': 'डेटा और बैकअप',
  'Security': 'सुरक्षा',
  'Information': 'जानकारी',
  'Light': 'लाइट',
  'Dark': 'डार्क',
  'System': 'सिस्टम',
  'Logo colours': 'लोगो के रंग',
  'More colours': 'और रंग',
  '@name accent': '@name रंग',
  'Settings saved.': 'सेटिंग्स सेव हो गईं।',
  'Loading your settings': 'आपकी सेटिंग्स लोड हो रही हैं',
  'Currency': 'मुद्रा',
  'Date format': 'तारीख का फ़ॉर्मैट',
  'Number format': 'संख्या का फ़ॉर्मैट',
  'First day of the week': 'हफ़्ते का पहला दिन',
  'Default account': 'डिफ़ॉल्ट अकाउंट',
  'Pre-selected on new transactions': 'नए लेन-देन में पहले से चुना हुआ',
  'My UPI ID': 'मेरी UPI ID',
  'Pay link in reminders and khata statements':
      'रिमाइंडर और खाता स्टेटमेंट में पेमेंट लिंक',
  'Not set': 'सेट नहीं',
  'Categories': 'श्रेणियाँ',
  'Add your own income and expense categories':
      'आमदनी और खर्च की अपनी श्रेणियाँ जोड़ें',
  'First account': 'पहला अकाउंट',
  'Lakh grouping, as used in India': 'लाख वाली गिनती, जैसी भारत में होती है',
  'Thousands grouping': 'हज़ार वाली गिनती',
  'UPI ID': 'UPI ID',
  'name@bank': 'name@bank',
  'Leave empty to remove': 'हटाने के लिए खाली छोड़ें',
  'Cancel': 'रद्द करें',
  'Save': 'सेव करें',
  'Export data': 'डेटा एक्सपोर्ट करें',
  'Export transactions, accounts & reports to CSV, Excel, or PDF':
      'लेन-देन, अकाउंट और रिपोर्ट CSV, Excel या PDF में एक्सपोर्ट करें',
  'Backup & restore': 'बैकअप और रिस्टोर',
  'Create a full offline backup or restore previous data':
      'पूरा ऑफ़लाइन बैकअप बनाएँ या पुराना डेटा वापस लाएँ',
  'Change password': 'पासवर्ड बदलें',
  'Sign out of this device': 'इस डिवाइस से साइन आउट करें',
  'Delete account': 'अकाउंट डिलीट करें',
  'Permanently removes your data': 'आपका डेटा हमेशा के लिए हटा देता है',
  'Privacy policy': 'प्राइवेसी पॉलिसी',
  'Terms of service': 'सेवा की शर्तें',
  'Cloud sync': 'क्लाउड सिंक',
  'Sync queue & connection status': 'सिंक कतार और कनेक्शन की स्थिति',
  'About': 'ऐप के बारे में',
  'Version @version': 'वर्ज़न @version',
  'Indian rupee': 'भारतीय रुपया',
  'US dollar': 'अमेरिकी डॉलर',
  'Euro': 'यूरो',
  'British pound': 'ब्रिटिश पाउंड',
  'UAE dirham': 'यूएई दिरहम',
  'Singapore dollar': 'सिंगापुर डॉलर',
  'Australian dollar': 'ऑस्ट्रेलियाई डॉलर',
  'Canadian dollar': 'कनाडाई डॉलर',
  'Japanese yen': 'जापानी येन',
  'Monday': 'सोमवार',
  'Sunday': 'रविवार',

  // Notification settings
  'Notifications are not available on this device. Reminders are still saved and shown in the app.':
      'इस डिवाइस पर सूचनाएँ उपलब्ध नहीं हैं। रिमाइंडर फिर भी सेव होते हैं और ऐप में दिखते हैं।',
  'Turn all notifications on or off': 'सभी सूचनाएँ चालू या बंद करें',
  'Alert me when a reminder is due': 'रिमाइंडर का समय होने पर बताएँ',
  'Budget alerts': 'बजट अलर्ट',
  'When spending reaches 75%, 90% or 100% of a budget':
      'जब खर्च बजट के 75%, 90% या 100% तक पहुँचे',
  'Recurring transactions': 'नियमित लेन-देन',
  'When a recurring transaction is recorded': 'जब कोई नियमित लेन-देन दर्ज हो',
  'Sound': 'आवाज़',
  'Play a sound with notifications': 'सूचनाओं के साथ आवाज़ चलाएँ',
  'Vibration': 'वाइब्रेशन',
  'Vibrate with notifications': 'सूचनाओं के साथ वाइब्रेट करें',
  'Exact reminder times': 'रिमाइंडर का सटीक समय',
  'Without this, reminders can arrive a few minutes late.':
      'इसके बिना रिमाइंडर कुछ मिनट देर से आ सकते हैं।',
  'Allow': 'अनुमति दें',

  // App lock
  'App lock': 'ऐप लॉक',
  'Ask for fingerprint, face or screen lock every time the app opens':
      'हर बार ऐप खुलने पर फ़िंगरप्रिंट, फ़ेस या स्क्रीन लॉक माँगें',

  // Accounts on this device and sign-out
  '@count accounts on this device': 'इस डिवाइस पर @count अकाउंट',
  'Sign in to another account': 'दूसरे अकाउंट में साइन इन करें',
  'Remove account?': 'अकाउंट हटाएँ?',
  'Remove @name (@email) from this device? You can sign in to it again later.':
      '@name (@email) को इस डिवाइस से हटाएँ? आप बाद में फिर से साइन इन कर सकते हैं।',
  'Remove': 'हटाएँ',
  'Remove account': 'अकाउंट हटाएँ',
  'Discard unsynced changes?': 'बिना सिंक हुए बदलाव छोड़ दें?',
  'Sign Out': 'साइन आउट',
  'Are you sure you want to sign out of your account?':
      'क्या आप सच में अपने अकाउंट से साइन आउट करना चाहते हैं?',
  '@count change has not reached the server yet. Signing out removes them from this device. Connect to the internet and let them sync to keep them.':
      '@count बदलाव अभी सर्वर तक नहीं पहुँचा है। साइन आउट करने पर यह इस डिवाइस से हट जाएगा। इसे बचाने के लिए इंटरनेट से जुड़ें और सिंक होने दें।',
  '@count changes have not reached the server yet. Signing out removes them from this device. Connect to the internet and let them sync to keep them.':
      '@count बदलाव अभी सर्वर तक नहीं पहुँचे हैं। साइन आउट करने पर ये इस डिवाइस से हट जाएँगे। इन्हें बचाने के लिए इंटरनेट से जुड़ें और सिंक होने दें।',
  'You will switch to @name (@email).': 'आप @name (@email) पर चले जाएँगे।',
  'Sign out': 'साइन आउट करें',

  // App bar menu and exit
  'More options': 'और विकल्प',
  'Profile': 'प्रोफ़ाइल',
  'Notifications, @count unread': 'सूचनाएँ, @count बिना पढ़ी',
  'Exit App': 'ऐप बंद करें',
  'Are you sure you want to exit the app?':
      'क्या आप सच में ऐप बंद करना चाहते हैं?',
  'Exit': 'बंद करें',
};
