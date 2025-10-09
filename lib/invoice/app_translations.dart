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
      'total': 'Total',
      'category': 'Category',
      'categories': 'Categories',
      'description': 'Description',
      'amount': 'Amount',
      'date': 'Date',
      'close': 'Close',

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
      'transactions_add_income': 'Income',
      'transactions_add_expense': 'Expense',
      'transactions_delete_title': 'Delete transaction?',
      'transactions_delete_confirm':
          'This action is permanent. Are you sure you want to delete this transaction?',
      'transactions_deleted_success': 'Transaction deleted',
      'transactions_end_of_list': 'End of list',
      'transactions_load_more': 'Load More',
      'transactions_no_transactions': 'No transactions found for this period.',

      // Add Transaction Page
      'add_transaction_title': 'Add Transaction',
      'edit_transaction_title': 'Edit Transaction',
      'add_category_title': 'Add New Category',
      'category_name': 'Category Name',
      'save_transaction': 'Save Transaction',

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
      'total': 'Jumla',
      'category': 'Kategoria',
      'categories': 'Kategoria',
      'description': 'Maelezo',
      'amount': 'Kiasi',
      'date': 'Tarehe',
      'close': 'Funga',

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
      'transactions_add_income': 'Mapato',
      'transactions_add_expense': 'Matumizi',
      'transactions_delete_title': 'Futa muamala?',
      'transactions_delete_confirm':
          'Kitendo hiki ni cha kudumu. Una uhakika unataka kufuta muamala huu?',
      'transactions_deleted_success': 'Muamala umefutwa',
      'transactions_end_of_list': 'Mwisho wa orodha',
      'transactions_load_more': 'Pakia Zaidi',
      'transactions_no_transactions': 'Hakuna miamala kwa kipindi hiki.',

      // Add Transaction Page
      'add_transaction_title': 'Ongeza Muamala',
      'edit_transaction_title': 'Hariri Muamala',
      'add_category_title': 'Ongeza Kategoria Mpya',
      'category_name': 'Jina la Kategoria',
      'save_transaction': 'Hifadhi Muamala',

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
    },
  };
}
