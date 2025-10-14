import 'package:get/get.dart';

class AppTranslations extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
    'en_US': {
      // General
      'save': 'Save',
      'cancel': 'Cancel',
      'delete': 'Delete',
      'edit': 'Edit',
      'success': 'Success',
      'error': 'Error',
      'income': 'Income',
      'expense': 'Expense',
      'expenses': 'Expenses',
      'net': 'Net',
      'search': 'Search',
      'refresh': 'Refresh',
      'Clear': 'Clear',
      'total': 'Total',
      'category': 'Category',
      'categories': 'Categories',
      'description': 'Description',
      'details': 'Details',
      'amount': 'Amount',
      'date': 'Date',
      'close': 'Close',
      'Add': 'Add',

      // Home Page
      'home_title': 'TRA Receipt System',
      'home_create_receipt': 'Create New Receipt',
      'home_create_receipt_sub': 'Generate a new receipt with customer details',
      'home_view_receipts': 'View All Receipts',
      'home_view_receipts_sub': 'Browse and manage existing receipts',
      'home_view_invoices': 'View Invoices',
      'home_view_invoices_sub': 'Browse invoices you have saved',
      'home_generate_invoice': 'Generate Invoice',
      'home_generate_invoice_sub': 'Create and print a professional invoice',
      'home_finance_tracker': 'Expense & Income',
      'home_finance_tracker_sub': 'Track your business finances',
      'home_manage_categories': 'Manage Categories',
      'home_manage_categories_sub': 'Add or edit income/expense types',
      'home_analytics': 'Analytics & Insights',
      'home_analytics_sub': 'View financial charts and reports',
      'home_about': 'About',
      'home_about_sub': 'System information and help',
      'home_profile': 'Profile',
      'home_sign_out': 'Sign Out',

      // Login Page
      'login_title': 'TRA Receipt System',
      'login_subtitle': 'Sign in to continue',
      'login_email': 'Email Address',
      'login_password': 'Password',
      'login_sign_in': 'Sign In',
      'login_create_account': 'Create Account',
      'login_welcome_back': 'Welcome back!',

      // Transactions Page
      'transactions_title': 'Income & Expense',
      'transactions_export_pdf': 'Export as PDF',
      'transactions_clear_filters': 'Clear All Filters',
      'transactions_all_time': 'All Time',
      'transactions_today': 'Today',
      'transactions_this_week': 'This Week',
      'transactions_this_month': 'This Month',
      'transactions_custom_range': 'Custom Range',
      'Sort by': 'Sort by',
      'Date (Newest First)': 'Date (Newest First)',
      'Date (Oldest First)': 'Date (Oldest First)',
      'Amount (Highest First)': 'Amount (Highest First)',
      'Amount (Lowest First)': 'Amount (Lowest First)',
      'transactions_add_income': 'Income',
      'transactions_add_expense': 'Expense',
      'transactions_delete_title': 'Delete transaction?',
      'transactions_delete_confirm':
          'This action is permanent. Are you sure you want to delete this transaction?',
      'transactions_deleted_success': 'Transaction deleted',
      'transactions_end_of_list': 'End of list',
      'transactions_load_more': 'Load More',
      'transactions_no_transactions': 'No transactions found for this period.',
      'Today': 'Today',
      'Yesterday': 'Yesterday',
      'Export PDF': 'Export PDF',
      'Export Excel': 'Export Excel',
      'Analytics': 'Analytics',

      // Add Transaction Page
      'add_transaction_title': 'Add Transaction',
      'edit_transaction_title': 'Edit Transaction',
      'add_category_title': 'Add New Category',
      'category_name': 'Category Name',
      'save_transaction': 'Save Transaction',
      'Back online - transactions will sync automatically':
          'Back online - transactions will sync automatically',
      'No internet connection - transactions will be saved offline':
          'No internet connection - transactions will be saved offline',
      'Connected': 'Connected',
      'Offline Mode': 'Offline Mode',
      'Sync Complete': 'Sync Complete',
      'Offline transactions have been synced':
          'Offline transactions have been synced',
      'Sync Error': 'Sync Error',
      'Failed to sync some offline transactions':
          'Failed to sync some offline transactions',
      'Category will be saved offline and synced when connection is restored.':
          'Category will be saved offline and synced when connection is restored.',
      'Transaction saved successfully': 'Transaction saved successfully',
      'Saved Offline': 'Saved Offline',
      'Transaction saved offline and will sync when connection is restored':
          'Transaction saved offline and will sync when connection is restored',

      // Categories Page
      'categories_title': 'Manage Categories',
      'categories_no_categories': 'No categories found. Tap + to add one.',
      'categories_delete_confirm': 'Are you sure you want to delete "{name}"?',

      // Profile Page
      'profile_title': 'Company Profile',
      'profile_language': 'Language',
      'profile_save_changes': 'Save Changes',
      'profile_uploading': 'Uploading...',
      'profile_company_details': 'Company Details',
      'profile_payment_details': 'Payment Details',
      'profile_branding': 'Branding & Theming',
      'analytics_all': 'All',
      'analytics_financial_overview': 'Financial Overview',
      'analytics_total_income': 'Total Income',
      'analytics_total_expense': 'Total Expense',
      'analytics_transactions': 'Transactions',
      'analytics_no_cash_flow_data': 'No data available for cash flow analysis',
      'analytics_cash_flow_trend': 'Cash Flow Trend',
      'analytics_no_category_data': 'No category data',
      'analytics_top_spending_categories': 'Top Spending Categories',
      'analytics_top_income_sources': 'Top Income Sources',
      'analytics_category_distribution': 'Category Distribution',
      'analytics_top_categories': 'Top Categories',
      'analytics_no_frequency_data': 'No frequency data available',
      'analytics_transaction_pattern': 'Transaction Pattern',
      'analytics_ai_insights': 'AI Insights',
      'analytics_positive_cash_flow': 'Positive Cash Flow',
      'analytics_positive_cash_flow_desc':
          'Great! Your income exceeds expenses by',
      'analytics_healthy_financial_position':
          'This is a healthy financial position.',
      'analytics_negative_cash_flow': 'Action Required: Negative Cash Flow',
      'analytics_negative_cash_flow_desc':
          'Your expenses are higher than your income by',
      'analytics_negative_cash_flow_suggestion':
          'Consider reviewing spending habits or finding new income streams.',
      'analytics_balanced_budget': 'Balanced Budget',
      'analytics_balanced_budget_desc':
          'Your income and expenses are balanced. Look for opportunities to increase your savings.',
      'analytics_top_spending_area': 'Top Spending Area',
      'analytics_top_spending_area_desc1': 'Your highest spending is in',
      'analytics_top_spending_area_desc2': 'making up',
      'analytics_top_spending_area_desc3':
          'of total expenses. Review this category for potential savings.',
      'analytics_suggestion_diversify_spending':
          'Suggestion: Diversify Spending',
      'analytics_suggestion_diversify_spending_desc':
          'A large portion of your budget goes to',
      'analytics_suggestion_diversify_spending_suggestion':
          'Setting a specific budget for this category could improve your financial flexibility.',
      'analytics_busiest_day': 'Busiest Transaction Day',
      'analytics_busiest_day_desc': 'You tend to make the most transactions on',
      'analytics_busiest_day_suggestion':
          'Being mindful of spending on this day could help manage your budget.',
      'analytics_avg_expense_value': 'Average Expense Value',
      'analytics_avg_expense_value_desc': 'Your average expense transaction is',
      'analytics_avg_expense_value_suggestion':
          'Tracking small expenses can lead to big savings over time.',
      'analytics_not_enough_data': 'Not Enough Data',
      'analytics_not_enough_data_desc':
          'Add more transactions to unlock powerful AI-driven insights and suggestions for your financial health.',
      'analytics_report_title': 'Analytics Report',
      'PDF saved': 'PDF saved',
      'Week': 'Week',
      'Day': 'Day',
      'Month': 'Month',
      'Year': 'Year',
      'Monday': 'Monday',
      'Tuesday': 'Tuesday',
      'Wednesday': 'Wednesday',
      'Thursday': 'Thursday',
      'Friday': 'Friday',
      'Saturday': 'Saturday',
      'Sunday': 'Sunday',
      'PDF Export Error': 'PDF Export Error',
      'analytics_transactions_for': 'Transactions for',
      'analytics_last_3_months': 'Last 3 Months',
      'analytics_this_year': 'This Year',
      'Other': 'Other',
      'Network timeout. Please check your connection.':
          'Network timeout. Please check your connection.',
      'Failed to load analytics data: ': 'Failed to load analytics data: ',
    },
    'sw_TZ': {
      // General
      'save': 'Hifadhi',
      'cancel': 'Ghairi',
      'delete': 'Futa',
      'edit': 'Hariri',
      'success': 'Imefanikiwa',
      'error': 'Hitilafu',
      'income': 'Mapato',
      'expense': 'Matumizi',
      'expenses': 'Matumizi',
      'net': 'Jumla Halisi',
      'search': 'Tafuta',
      'refresh': 'Burudisha',
      'Clear': 'Futa',
      'total': 'Jumla',
      'category': 'Kategoria',
      'categories': 'Kategoria',
      'description': 'Maelezo',
      'details': 'Maelezo',
      'amount': 'Kiasi',
      'date': 'Tarehe',
      'close': 'Funga',
      'Add': 'Ongeza',

      // Home Page
      'home_title': 'Mfumo wa Risiti wa TRA',
      'home_create_receipt': 'Tengeneza Risiti Mpya',
      'home_create_receipt_sub': 'Tengeneza risiti mpya na maelezo ya mteja',
      'home_view_receipts': 'Angalia Risiti Zote',
      'home_view_receipts_sub': 'Vinjari na dhibiti risiti zilizopo',
      'home_view_invoices': 'Angalia ankara',
      'home_view_invoices_sub': 'Vinjari ankara ulizohifadhi',
      'home_generate_invoice': 'Tengeneza Ankara',
      'home_generate_invoice_sub': 'Unda na chapisha ankara ya kitaalamu',
      'home_finance_tracker': 'Matumizi na Mapato',
      'home_finance_tracker_sub': 'Fuatilia fedha za biashara yako',
      'home_manage_categories': 'Dhibiti Kategoria',
      'home_manage_categories_sub': 'Ongeza au hariri aina za mapato/matumizi',
      'home_analytics': 'Uchambuzi na Ripoti',
      'home_analytics_sub': 'Angalia chati za kifedha na ripoti',
      'home_about': 'Kuhusu',
      'home_about_sub': 'Taarifa za mfumo na msaada',
      'home_profile': 'Wasifu',
      'home_sign_out': 'Toka Nje',

      // Login Page
      'login_title': 'Mfumo wa Risiti wa TRA',
      'login_subtitle': 'Ingia ili uendelee',
      'login_email': 'Anwani ya Barua Pepe',
      'login_password': 'Nenosiri',
      'login_sign_in': 'Ingia',
      'login_create_account': 'Tengeneza Akaunti',
      'login_welcome_back': 'Karibu tena!',

      // Transactions Page
      'transactions_title': 'Mapato na Matumizi',
      'transactions_export_pdf': 'Hamisha kama PDF',
      'transactions_clear_filters': 'Futa Vichujio Vyote',
      'transactions_all_time': 'Muda Wote',
      'transactions_today': 'Leo',
      'transactions_this_week': 'Wiki Hii',
      'transactions_this_month': 'Mwezi Huu',
      'transactions_custom_range': 'Chagua Kipindi',
      'Sort by': 'Panga kwa',
      'Date (Newest First)': 'Tarehe (Mpya Kwanza)',
      'Date (Oldest First)': 'Tarehe (Zamani Kwanza)',
      'Amount (Highest First)': 'Kiasi (Kikubwa Kwanza)',
      'Amount (Lowest First)': 'Kiasi (Kidogo Kwanza)',
      'transactions_add_income': 'Mapato',
      'transactions_add_expense': 'Matumizi',
      'transactions_delete_title': 'Futa muamala?',
      'transactions_delete_confirm':
          'Kitendo hiki ni cha kudumu. Una uhakika unataka kufuta muamala huu?',
      'transactions_deleted_success': 'Muamala umefutwa',
      'transactions_end_of_list': 'Mwisho wa orodha',
      'transactions_load_more': 'Pakia Zaidi',
      'transactions_no_transactions': 'Hakuna miamala kwa kipindi hiki.',
      'Today': 'Leo',
      'Yesterday': 'Jana',
      'Export PDF': 'Hamisha PDF',
      'Export Excel': 'Hamisha Excel',
      'Analytics': 'Uchambuzi',

      // Add Transaction Page
      'add_transaction_title': 'Ongeza Muamala',
      'edit_transaction_title': 'Hariri Muamala',
      'add_category_title': 'Ongeza Kategoria Mpya',
      'category_name': 'Jina la Kategoria',
      'save_transaction': 'Hifadhi Muamala',
      'Back online - transactions will sync automatically':
          'Umerudi mtandaoni - miamala itasawazishwa kiotomatiki',
      'No internet connection - transactions will be saved offline':
          'Hakuna muunganisho wa intaneti - miamala itahifadhiwa nje ya mtandao',
      'Connected': 'Imeunganishwa',
      'Offline Mode': 'Hali ya Nje ya Mtandao',
      'Sync Complete': 'Usawazishaji Umekamilika',
      'Offline transactions have been synced':
          'Miamala ya nje ya mtandao imesawazishwa',
      'Sync Error': 'Hitilafu ya Usawazishaji',
      'Failed to sync some offline transactions':
          'Imeshindwa kusawazisha baadhi ya miamala ya nje ya mtandao',
      'Category will be saved offline and synced when connection is restored.':
          'Kategoria itahifadhiwa nje ya mtandao na kusawazishwa muunganisho utakapopatikana.',
      'Transaction saved successfully': 'Muamala umehifadhiwa kikamilifu',
      'Saved Offline': 'Imehifadhiwa Nje ya Mtandao',
      'Transaction saved offline and will sync when connection is restored':
          'Muamala umehifadhiwa nje ya mtandao na utasawazishwa muunganisho utakapopatikana',

      // Categories Page
      'categories_title': 'Dhibiti Kategoria',
      'categories_no_categories': 'Hakuna kategoria. Gusa + kuongeza.',
      'categories_delete_confirm': 'Una uhakika unataka kufuta "{name}"?',

      // Profile Page
      'profile_title': 'Wasifu wa Kampuni',
      'profile_language': 'Lugha',
      'profile_save_changes': 'Hifadhi Mabadiliko',
      'profile_uploading': 'Inapakia...',
      'profile_company_details': 'Maelezo ya Kampuni',
      'profile_payment_details': 'Maelezo ya Malipo',
      'profile_branding': 'Chapa na Mandhari',
      'analytics_all': 'Zote',
      'analytics_financial_overview': 'Muhtasari wa Kifedha',
      'analytics_total_income': 'Jumla ya Mapato',
      'analytics_total_expense': 'Jumla ya Matumizi',
      'analytics_transactions': 'Miamala',
      'analytics_no_cash_flow_data':
          'Hakuna data ya uchambuzi wa mtiririko wa fedha',
      'analytics_cash_flow_trend': 'Mwenendo wa Mtiririko wa Fedha',
      'analytics_no_category_data': 'Hakuna data ya kategoria',
      'analytics_top_spending_categories': 'Kategoria za Juu za Matumizi',
      'analytics_top_income_sources': 'Vyanzo Vikuu vya Mapato',
      'analytics_category_distribution': 'Mgawanyo wa Kategoria',
      'analytics_top_categories': 'Kategoria za Juu',
      'analytics_no_frequency_data': 'Hakuna data ya marudio ya miamala',
      'analytics_transaction_pattern': 'Mpangilio wa Miamala',
      'analytics_ai_insights': 'Ufahamu wa AI',
      'analytics_positive_cash_flow': 'Mtiririko Chanya wa Fedha',
      'analytics_positive_cash_flow_desc':
          'Safi! Mapato yako yanazidi matumizi kwa',
      'analytics_healthy_financial_position': 'Hii ni hali nzuri ya kifedha.',
      'analytics_negative_cash_flow':
          'Hatua Inahitajika: Mtiririko Hasi wa Fedha',
      'analytics_negative_cash_flow_desc':
          'Matumizi yako ni ya juu kuliko mapato kwa',
      'analytics_negative_cash_flow_suggestion':
          'Fikiria kupitia upya tabia za matumizi au kutafuta vyanzo vipya vya mapato.',
      'analytics_balanced_budget': 'Bajeti Sawa',
      'analytics_balanced_budget_desc':
          'Mapato na matumizi yako yanasawazika. Tafuta fursa za kuongeza akiba yako.',
      'analytics_top_spending_area': 'Eneo Kuu la Matumizi',
      'analytics_top_spending_area_desc1': 'Matumizi yako makubwa yapo kwenye',
      'analytics_top_spending_area_desc2': 'ikiwa ni',
      'analytics_top_spending_area_desc3':
          'ya jumla ya matumizi. Pitia kategoria hii kwa uwezekano wa kuweka akiba.',
      'analytics_suggestion_diversify_spending':
          'Pendekezo: Tofautisha Matumizi',
      'analytics_suggestion_diversify_spending_desc':
          'Sehemu kubwa ya bajeti yako inaenda kwa',
      'analytics_suggestion_diversify_spending_suggestion':
          'Kuweka bajeti maalum kwa kategoria hii kunaweza kuboresha unyumbufu wako wa kifedha.',
      'analytics_busiest_day': 'Siku yenye Miamala Mingi Zaidi',
      'analytics_busiest_day_desc':
          'Unaelekea kufanya miamala mingi zaidi siku za',
      'analytics_busiest_day_suggestion':
          'Kuwa mwangalifu na matumizi siku hii kunaweza kusaidia kudhibiti bajeti yako.',
      'analytics_avg_expense_value': 'Wastani wa Thamani ya Matumizi',
      'analytics_avg_expense_value_desc':
          'Wastani wa muamala wako wa matumizi ni',
      'analytics_avg_expense_value_suggestion':
          'Kufuatilia matumizi madogo kunaweza kusababisha akiba kubwa baada ya muda.',
      'analytics_not_enough_data': 'Hakuna Data ya Kutosha',
      'analytics_not_enough_data_desc':
          'Ongeza miamala zaidi ili kufungua ufahamu na mapendekezo ya AI kwa afya yako ya kifedha.',
      'analytics_report_title': 'Ripoti ya Uchambuzi',
      'PDF saved': 'PDF imehifadhiwa',
      'Week': 'Wiki',
      'Day': 'Siku',
      'Month': 'Mwezi',
      'Year': 'Mwaka',
      'Monday': 'Jumatatu',
      'Tuesday': 'Jumanne',
      'Wednesday': 'Jumatano',
      'Thursday': 'Alhamisi',
      'Friday': 'Ijumaa',
      'Saturday': 'Jumamosi',
      'Sunday': 'Jumapili',
      'PDF Export Error': 'Hitilafu ya Kuhamisha PDF',
      'analytics_transactions_for': 'Miamala ya',
      'analytics_last_3_months': 'Miezi 3 Iliyopita',
      'analytics_this_year': 'Mwaka Huu',
      'Other': 'Nyingine',
      'Network timeout. Please check your connection.':
          'Muda wa mtandao umeisha. Tafadhali angalia muunganisho wako.',
      'Failed to load analytics data: ':
          'Imeshindwa kupakia data ya uchambuzi: ',
    },
  };
}
