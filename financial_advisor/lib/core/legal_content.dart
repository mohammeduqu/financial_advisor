// Original draft based on the app's actual data flows. Complete the operator
// details and obtain jurisdiction-specific review before publishing as final.
// Provider references: https://developers.openai.com/api/docs/guides/your-data
// and https://serpapi.com/legal. Reviewed 2026-09-29.
import 'legal_acceptance.dart';

class LegalSection {
  final String id;
  final String title;
  final String body;

  const LegalSection({
    required this.id,
    required this.title,
    required this.body,
  });
}

class LegalDocument {
  final String title;
  final String introduction;
  final List<LegalSection> sections;

  const LegalDocument({
    required this.title,
    required this.introduction,
    required this.sections,
  });
}

LegalDocument privacyDocument(String language) =>
    language == 'ar' ? _privacyAr : _privacyEn;

LegalDocument termsDocument(String language) =>
    language == 'ar' ? _termsAr : _termsEn;

const _operatorEn = LegalSection(
  id: 'operator',
  title: 'Operator & contact information',
  body:
      'Tadbeer is the application name. The legal operator’s name, operating '
      'country, contact address and privacy/support email have not yet been '
      'provided. This draft is incomplete until those details are added and '
      'verified before public release. There is currently no published contact '
      'channel here for privacy requests or complaints.\n\n'
      'The service providers named below are not the operator of Tadbeer.',
);

const _operatorAr = LegalSection(
  id: 'operator',
  title: 'الجهة المشغّلة ووسائل التواصل',
  body:
      'تدبير هو اسم التطبيق. لم تُحدّد بعد هوية الجهة المشغّلة قانونيًا، ودولة '
      'التشغيل، وعنوان التواصل، والبريد الإلكتروني للخصوصية والدعم. تظل هذه '
      'المسودة غير مكتملة حتى إضافة هذه المعلومات والتحقق منها قبل الإطلاق '
      'العام. لا توجد حاليًا وسيلة تواصل منشورة هنا لتقديم طلبات الخصوصية أو '
      'الشكاوى.\n\n'
      'مقدّمو الخدمات المذكورون أدناه ليسوا الجهة المشغّلة لتطبيق تدبير.',
);

const _privacyEn = LegalDocument(
  title: 'Privacy notice',
  introduction:
      'Draft for review · Updated 29 September 2026\n'
      'Document version: $currentLegalVersion\n\n'
      'This notice explains how the current version of Tadbeer handles '
      'information when you manage your finances, scan receipts, request AI '
      'insights or search for products. Operator details and deployment-specific '
      'retention, legal grounds and transfer arrangements still need to be '
      'confirmed before this notice is published as final.',
  sections: [
    _operatorEn,
    LegalSection(
      id: 'information',
      title: '1. Information you provide',
      body:
          'Profile information includes your chosen name, country, currency and '
          'language. Financial records can include income, expenses, merchants, '
          'amounts, dates, categories, notes, budgets, savings goals, recurring '
          'schedules and invoice details. The app also handles receipt images '
          'you choose to scan or save, product search terms, search preferences '
          'and comparison history. When you confirm agreement, the document '
          'version, acceptance time and displayed language are saved with '
          'your profile.\n\n'
          'A name is required to finish setup. You can change profile preferences '
          'later. Receipt scanning, AI insights and product searches are '
          'optional; you can enter financial records manually. Do not include '
          'passwords, bank login credentials, full payment-card details, identity '
          'documents or unnecessary information about other people.',
    ),
    LegalSection(
      id: 'purposes',
      title: '2. Why information is processed',
      body:
          'The app uses your entries to maintain your ledger, apply recurring '
          'schedules, calculate budgets and charts, and display summaries in '
          'your chosen currency and language. The country selected in product-'
          'search settings guides shopping results and is separate from your '
          'profile country; it is not a GPS location. Requested invoice and AI '
          'features use the data described below to produce their results.\n\n'
          'Displaying this notice is not blanket consent to additional uses of '
          'your data. Processing must have a lawful basis under the law that '
          'applies to the operator and user. Any required consent for a new '
          'purpose must be obtained separately.',
    ),
    LegalSection(
      id: 'ai',
      title: '3. Invoice scanning & AI insights',
      body:
          'When you scan a receipt, its image goes through Tadbeer’s backend to '
          'OpenAI for extraction. All visible information in that image may be '
          'processed, including names or card fragments printed on the receipt. '
          'Crop or cover unnecessary details before uploading. The backend '
          'processes uploads in memory without intentionally saving the '
          'uploaded image as a server file; a receipt copy may be saved with '
          'your local expense.\n\n'
          'When you press the AI insights button, the app sends relevant '
          'selected and previous month expense dates, amounts, categories and '
          'merchant names, income dates and amounts, budgets, recurrence '
          'information, currency and language to the backend. A financial '
          'summary, including top merchant names, is sent to OpenAI. This '
          'insight request does not include your profile name, receipt images '
          'or transaction notes.\n\n'
          'AI results are suggestions for you to review. Tadbeer does not use '
          'them to approve credit, move money or make binding decisions for you.',
    ),
    LegalSection(
      id: 'shopping',
      title: '4. Product searches & external websites',
      body:
          'Pressing Search stores sends the product name and selected country, '
          'language and price settings through the backend to SerpAPI to obtain '
          'shopping results. Ordinary product-name search does not send the '
          'query to OpenAI. Avoid entering personal or financial information in '
          'a product search.\n\n'
          'When you confirm a price comparison for an invoice, the full '
          'reviewed invoice is sent to the backend: merchant, invoice number, '
          'date, amounts, currency, category and all invoice items, including '
          'items not selected for search. Selected product information is '
          'also sent. SerpAPI receives the resulting product search terms, '
          'not the full invoice.\n\n'
          'Product images and store icons are loaded from external image '
          'services. Those services receive network requests that can disclose '
          'your IP address and normal browser or device request information. '
          'Opening a store link takes you to an external merchant whose own '
          'privacy notice and sales terms apply. Tadbeer does not operate '
          'the merchant’s checkout.',
    ),
    LegalSection(
      id: 'storage',
      title: '5. Storage & retention',
      body:
          'Your profile, financial records, recurring schedules, budgets, '
          'goals and saved receipt copies are stored in the app’s storage on '
          'your device or browser. The current profile is not a cloud account '
          'with guaranteed backup or synchronization. Comparison history '
          'contains up to 20 saved comparisons and is also limited by storage '
          'size. Search preferences are saved separately.\n\n'
          'Generated insights stay in the current app session until you clear '
          'them or close the app. Search queries and results are also cached on '
          'the backend. Cached prices normally remain valid for 12 hours, but '
          'that is a freshness period, not a guaranteed deletion deadline. '
          'Expired cache records are removed during cache access or cleanup.\n\n'
          'Hosting services may keep operational or access logs, including '
          'network identifiers. The deployed hosting location, log retention '
          'and backup retention periods have not yet been confirmed for this '
          'draft. Provider retention is separate from app storage.',
    ),
    LegalSection(
      id: 'providers',
      title: '6. Service providers & international processing',
      body:
          'Requested features use backend hosting, OpenAI for AI processing '
          'and SerpAPI for shopping search. These providers and their '
          'subprocessors may process data outside your country. This draft '
          'does not establish a particular hosting region or a legal transfer '
          'mechanism; the operator must verify the applicable requirements '
          'before public deployment.\n\n'
          'OpenAI states that API content is not used for training by default '
          'unless the customer opts in. Its default abuse-monitoring retention '
          'can be up to 30 days, with legal and safety exceptions. The app’s '
          'request not to store responses does not guarantee zero retention. '
          'SerpAPI states that standard search data is retained for 31 days, '
          'subject to its policy and deletion/backup conditions. No special '
          'zero-retention arrangement is promised by this app.\n\n'
          'Provider details:\n'
          'https://developers.openai.com/api/docs/guides/your-data\n'
          'https://serpapi.com/legal',
    ),
    LegalSection(
      id: 'controls',
      title: '7. Your controls & deletion',
      body:
          'You can edit your profile and financial entries, manage recurring '
          'schedules, remove individual saved comparisons, and clear displayed '
          'AI insights. Clear saved data removes the app’s saved financial '
          'profile, acceptance record, records, receipt copies, schedules, budgets, goals and '
          'comparison history. Keep any records you need before confirming '
          'deletion.\n\n'
          'This action does not delete original photos in your gallery, '
          'separately saved search preferences, browser or device backups, '
          'backend caches, hosting logs or records already held by providers. '
          'Clearing an insight removes the displayed result, not the data '
          'previously sent to generate it.\n\n'
          'You can stop new optional requests by not using their buttons and '
          'revoke camera/photo permissions in device settings. That does not '
          'recall a request already processed.',
    ),
    LegalSection(
      id: 'rights',
      title: '8. Privacy rights & complaints',
      body:
          'Depending on applicable law, you may have rights to information, '
          'access, a copy, correction or deletion of personal data, and to '
          'withdraw consent where processing relies on consent. Requests may '
          'require proportionate identity verification and may be subject to '
          'lawful exceptions. You may complain to the relevant data protection '
          'authority, including SDAIA where Saudi personal data protection law '
          'applies.\n\n'
          'The operator’s request channel must be completed in the contact '
          'section above before release. App deletion controls do not replace '
          'your legal rights or the operator’s obligations.',
    ),
    LegalSection(
      id: 'security',
      title: '9. Permissions & security limits',
      body:
          'Camera or photo access is used when you choose an image. You can '
          'manage those permissions in your operating system. Country '
          'selection does not require GPS access. This version does not '
          'include an advertising or analytics SDK in the application code. '
          'External sites and service providers have separate practices.\n\n'
          'The current build does not provide an app sign-in security boundary '
          'or app-level encryption for saved records. Backend connection '
          'security depends on deployment and an encrypted connection is not '
          'guaranteed by this build. Protect access to your device and avoid '
          'submitting unnecessary sensitive details. These limits do not '
          'remove the operator’s legal responsibility to protect personal data.',
    ),
    LegalSection(
      id: 'children',
      title: '10. Children & information about others',
      body:
          'Tadbeer is intended for adults managing their own finances. It is '
          'not designed for children or for collecting children’s information. '
          'Only provide another person’s information where you have lawful '
          'authority to do so, and remove details that the requested feature '
          'does not need. A suspected inappropriate submission should be '
          'reported through the operator’s contact channel once published.',
    ),
    LegalSection(
      id: 'changes',
      title: '11. Changes to this notice',
      body:
          'The date above identifies this draft. The operator must keep the '
          'notice aligned with actual features and data handling, explain '
          'material changes before they apply, and obtain any new consent '
          'required by law. Changes cannot remove statutory rights. A privacy '
          'notice does not itself establish compliance, authorize unrestricted '
          'use of data, or replace appropriate technical safeguards.',
    ),
  ],
);

const _termsEn = LegalDocument(
  title: 'Terms of use',
  introduction:
      'Draft for review · Updated 29 September 2026\n'
      'Document version: $currentLegalVersion\n\n'
      'These proposed terms describe the use of Tadbeer for personal financial '
      'record keeping and spending management. Read them together with the '
      'Privacy notice. They require review for the operator’s jurisdiction and '
      'completion of the details below before being issued as final terms. '
      'Viewing this draft does not record your acceptance. Checking the '
      'agreement box and pressing Get started or Continue saves your agreement '
      'to this version on this device. This record is not identity verification '
      'or consent to unrelated data processing.',
  sections: [
    _operatorEn,
    LegalSection(
      id: 'scope',
      title: '1. Purpose & eligibility',
      body:
          'Tadbeer helps you record income and expenses, plan budgets, review '
          'spending, scan receipts, generate AI summaries and compare selected '
          'shopping offers. It is intended for adults with legal capacity to '
          'agree to terms and for lawful personal use.\n\n'
          'The app does not hold funds, provide a bank account, execute '
          'payments, issue credit or manage investments. A profile name is a '
          'display preference and does not establish verified identity or a '
          'banking relationship.',
    ),
    LegalSection(
      id: 'records',
      title: '2. Your records & settings',
      body:
          'Enter accurate information and review amounts, dates, categories '
          'and merchants before saving. Totals and charts depend on the '
          'records you supply and are not independently verified bank '
          'balances. Keep original receipts and other records required for '
          'tax, accounting or legal purposes outside the app.\n\n'
          'Changing the account currency changes how the same numbers are '
          'labelled; it does not convert them at an exchange rate. Check the '
          'currency of external offers separately. Recurring and scheduled '
          'entries are bookkeeping records, not bank transfers, bill payments '
          'or proof that an obligation has been paid.',
    ),
    LegalSection(
      id: 'ai',
      title: '3. AI output & financial information',
      body:
          'Receipt extraction and AI insights can be incomplete, inaccurate '
          'or unsuitable for your circumstances. Review extracted details '
          'and treat recommendations as optional budgeting suggestions. '
          'No particular saving, financial outcome or accuracy level is '
          'guaranteed.\n\n'
          'The app does not replace advice from a qualified financial, tax, '
          'accounting or legal professional. Seek appropriate advice before '
          'making decisions with significant consequences. The limitations '
          'of AI do not excuse the operator from obligations imposed by law.',
    ),
    LegalSection(
      id: 'offers',
      title: '4. Shopping comparisons & merchants',
      body:
          'Search results reflect available provider data and may include '
          'different sizes, models, conditions or sellers. Sorting by displayed '
          'price does not guarantee the lowest total price or coverage of '
          'every store. Cached offers may be outdated. Confirm currency, '
          'availability, authenticity, shipping, taxes, returns and the final '
          'price with the merchant.\n\n'
          'A listing, image or store icon is not an endorsement or guarantee. '
          'Purchases, payment, delivery, refunds and warranties are arranged '
          'with the external seller under its terms. Tadbeer does not collect '
          'your purchase payment or act as the seller, and remains responsible '
          'for its own conduct to the extent required by law.',
    ),
    LegalSection(
      id: 'acceptable-use',
      title: '5. Acceptable use',
      body:
          'Use the app only for lawful purposes and submit material you own '
          'or have permission to process. Do not upload malicious software, '
          'impersonate others, infringe privacy or intellectual property, '
          'attempt unauthorized access, evade access controls, or overload '
          'the service through abusive automated requests.\n\n'
          'These conditions do not prohibit lawful security reporting, '
          'interoperability or other activities protected by applicable law.',
    ),
    LegalSection(
      id: 'ownership',
      title: '6. Your content & intellectual property',
      body:
          'You retain your rights in your financial records and uploaded '
          'material. Providing content for a requested feature permits only '
          'the handling needed to supply that feature, subject to the Privacy '
          'notice and applicable law; it does not transfer ownership of your '
          'content to the operator.\n\n'
          'The app’s software and branding, and third-party names, images, '
          'logos and other materials, remain subject to their respective '
          'owners’ rights and any applicable open-source licences. Access '
          'to the app does not grant ownership of those materials. No '
          'exclusive rights in AI-generated output are promised.',
    ),
    LegalSection(
      id: 'availability',
      title: '7. Availability, changes & charges',
      body:
          'Features depend on your device, connectivity and third-party '
          'services and may be unavailable during failures or maintenance. '
          'No uninterrupted operation or recovery of every record is '
          'promised. Keep independent copies of important information.\n\n'
          'The current app does not include a checkout for purchasing a '
          'Tadbeer subscription. Any future paid feature must disclose its '
          'price, billing conditions and cancellation terms and obtain the '
          'required agreement before charging. Your mobile data charges and '
          'purchases from external merchants are separate.',
    ),
    LegalSection(
      id: 'liability',
      title: '8. Responsibility & limits',
      body:
          'To the extent permitted by applicable law, the service is provided '
          'with the limitations described in these terms, without an additional '
          'promise that every result will be accurate or meet every individual '
          'purpose. Any exclusion of implied warranties applies only where '
          'lawfully permitted.\n\n'
          'The operator is not responsible for losses attributable solely to '
          'an external merchant or to use contrary to these terms, except '
          'where the law makes the operator responsible. Nothing excludes '
          'liability for fraud, intentional wrongdoing, gross negligence, '
          'unlawful personal-data handling, or any liability that cannot '
          'lawfully be limited. There is no blanket waiver of compensation '
          'or fixed zero-liability cap. Mandatory consumer rights remain '
          'unaffected.',
    ),
    LegalSection(
      id: 'ending-use',
      title: '9. Ending use & removing data',
      body:
          'You may stop using the app at any time and use its deletion '
          'controls. Review the Privacy notice for the scope of Clear saved '
          'data and the separate treatment of provider records, caches and '
          'backups. Deleting the app does not cancel a merchant order, a '
          'real-world recurring payment or a legal obligation.\n\n'
          'Where lawful and proportionate, access to online features may '
          'be restricted to address abuse, security incidents or legal '
          'requirements. Any restriction remains subject to applicable '
          'consumer and data protection rights.',
    ),
    LegalSection(
      id: 'disputes',
      title: '10. Questions, disputes & applicable law',
      body:
          'The operator’s verified contact details and operating country '
          'must be completed above. You may seek an informal resolution '
          'through that contact channel once available. Doing so is not '
          'a condition for making a lawful complaint or bringing a claim.\n\n'
          'Applicable mandatory law determines your rights and the '
          'competent authority or court. This draft does not select an '
          'exclusive foreign court, require arbitration, or waive your '
          'right to a regulator, court or remedy. No wording in these '
          'terms can guarantee that the operator will not face complaints '
          'or legal proceedings.',
    ),
    LegalSection(
      id: 'updates',
      title: '11. Updates & interpretation',
      body:
          'Material changes should be brought to your attention before '
          'they apply, with renewed agreement where required by law. '
          'A later version must not retroactively remove accrued rights. '
          'If a provision is unenforceable, the remaining provisions apply '
          'only to the extent permitted by law.\n\n'
          'English and Arabic versions are intended to describe the same '
          'conditions. No translation can remove protections required by '
          'applicable law. This draft still needs review and does not '
          'represent legal certification of the app.',
    ),
  ],
);

const _privacyAr = LegalDocument(
  title: 'إشعار الخصوصية',
  introduction:
      'مسودة للمراجعة · آخر تحديث: 29 سبتمبر 2026\n'
      'إصدار المستندات: $currentLegalVersion\n\n'
      'يوضح هذا الإشعار كيفية تعامل الإصدار الحالي من تدبير مع المعلومات عند '
      'إدارة الأموال، ومسح الفواتير، وطلب الملخصات الذكية، والبحث عن المنتجات. '
      'يلزم استكمال بيانات الجهة المشغّلة والتحقق من مدد الاحتفاظ والأسس '
      'النظامية وترتيبات نقل البيانات في بيئة التشغيل قبل اعتماد الإشعار '
      'بصورته النهائية.',
  sections: [
    _operatorAr,
    LegalSection(
      id: 'information',
      title: '1. المعلومات التي تقدمها',
      body:
          'تشمل بيانات الملف الشخصي الاسم المختار والدولة والعملة واللغة. '
          'وقد تتضمن السجلات المالية الدخل والمصروفات والتجار والمبالغ '
          'والتواريخ والتصنيفات والملاحظات والميزانيات وأهداف الادخار وجداول '
          'التكرار وتفاصيل الفواتير. كما يعالج التطبيق صور الفواتير التي '
          'تختار مسحها أو حفظها، وعبارات البحث عن المنتجات وتفضيلاته وسجل '
          'المقارنات. عند تأكيد الموافقة، يُحفظ إصدار المستندات ووقت '
          'الموافقة ولغة العرض مع ملفك الشخصي.\n\n'
          'يلزم إدخال اسم لإكمال الإعداد، ويمكن تعديل تفضيلات الملف الشخصي '
          'لاحقًا. مسح الفواتير والملخصات الذكية والبحث عن المنتجات ميزات '
          'اختيارية، ويمكن إدخال المعاملات يدويًا. لا تُدخل كلمات المرور '
          'أو بيانات الدخول البنكية أو بيانات بطاقات الدفع الكاملة أو '
          'وثائق الهوية أو معلومات غير لازمة عن الآخرين.',
    ),
    LegalSection(
      id: 'purposes',
      title: '2. أغراض معالجة المعلومات',
      body:
          'يستخدم التطبيق مدخلاتك لحفظ السجل المالي وتطبيق جداول التكرار '
          'وحساب الميزانيات والرسوم البيانية وعرض الملخصات بالعملة واللغة '
          'المختارتين. توجّه الدولة المختارة في إعدادات البحث نتائج التسوق، '
          'وهي مستقلة عن دولة الملف الشخصي ولا تمثل تحديدًا لموقعك عبر GPS. '
          'وتعالج ميزات الفواتير '
          'والذكاء الاصطناعي البيانات الموضحة أدناه لإنتاج النتائج المطلوبة.\n\n'
          'عرض هذا الإشعار لا يعني موافقة شاملة على استخدام بياناتك لأغراض '
          'إضافية. يجب أن تستند المعالجة إلى أساس نظامي وفق الأنظمة المنطبقة '
          'على المشغّل والمستخدم. وأي موافقة لازمة لغرض جديد يجب الحصول '
          'عليها بصورة منفصلة.',
    ),
    LegalSection(
      id: 'ai',
      title: '3. مسح الفواتير والملخصات الذكية',
      body:
          'عند مسح فاتورة، تُرسل صورتها عبر خادم تدبير إلى OpenAI لاستخراج '
          'التفاصيل. قد تشمل المعالجة كل ما يظهر في الصورة، بما فيه الأسماء '
          'أو أجزاء أرقام البطاقات المطبوعة. اقتطع أو أخفِ التفاصيل غير '
          'اللازمة قبل الإرسال. يعالج الخادم الصور في الذاكرة دون حفظ '
          'مقصود للصورة المرفوعة كملف على الخادم، وقد تُحفظ نسخة من '
          'الفاتورة مع المصروف على جهازك.\n\n'
          'عند الضغط على زر الملخصات الذكية، يرسل التطبيق إلى الخادم '
          'تواريخ ومبالغ وتصنيفات مصروفات الشهر المعني والشهر السابق '
          'وأسماء التجار، وتواريخ الدخل ومبالغه، والميزانيات ومعلومات '
          'التكرار والعملة واللغة. ويُرسل ملخص مالي يتضمن أبرز أسماء '
          'التجار إلى OpenAI. لا يتضمن طلب الملخص اسم ملفك الشخصي أو '
          'صور الفواتير أو ملاحظات المعاملات.\n\n'
          'النتائج الذكية اقتراحات تراجعها بنفسك. لا يستخدمها تدبير لمنح '
          'ائتمان أو نقل أموال أو اتخاذ قرارات ملزمة نيابةً عنك.',
    ),
    LegalSection(
      id: 'shopping',
      title: '4. البحث عن المنتجات والمواقع الخارجية',
      body:
          'عند الضغط على البحث في المتاجر، يُرسل اسم المنتج وإعدادات '
          'الدولة واللغة والسعر المختارة عبر الخادم إلى SerpAPI للحصول '
          'على نتائج التسوق. لا يرسل البحث المعتاد باسم المنتج عبارتك '
          'إلى OpenAI. تجنب إدخال معلومات شخصية أو مالية ضمن البحث.\n\n'
          'عند تأكيد مقارنة أسعار فاتورة، تُرسل الفاتورة المراجعة كاملة '
          'إلى الخادم: التاجر ورقم الفاتورة والتاريخ والمبالغ والعملة '
          'والتصنيف وجميع بنودها، بما فيها البنود غير المختارة للبحث. '
          'كما تُرسل معلومات المنتجات المختارة. تستقبل SerpAPI عبارات '
          'البحث الناتجة عن المنتجات، وليس الفاتورة كاملة.\n\n'
          'تُحمّل صور المنتجات وأيقونات المتاجر من خدمات صور خارجية. '
          'وتستقبل هذه الخدمات طلبات اتصال قد تكشف عنوان IP ومعلومات '
          'الطلب المعتادة للمتصفح أو الجهاز. فتح رابط متجر ينقلك إلى '
          'موقع خارجي يخضع لإشعار الخصوصية وشروط البيع الخاصة به. '
          'لا يدير تدبير عملية الدفع لدى المتجر.',
    ),
    LegalSection(
      id: 'storage',
      title: '5. التخزين والاحتفاظ بالبيانات',
      body:
          'يُحفظ ملفك الشخصي وسجلك المالي وجداول التكرار والميزانيات '
          'والأهداف ونسخ الفواتير المحفوظة في مساحة التطبيق على جهازك '
          'أو متصفحك. الملف الحالي ليس حسابًا سحابيًا يضمن النسخ '
          'الاحتياطي أو المزامنة. يحتفظ سجل المقارنات بما يصل إلى '
          '20 مقارنة، ويخضع أيضًا لحد حجم التخزين. تُحفظ تفضيلات '
          'البحث بشكل منفصل.\n\n'
          'تبقى الملخصات الذكية في جلسة التطبيق الحالية حتى مسحها '
          'أو إغلاق التطبيق. كما تُخزّن عبارات البحث ونتائجه مؤقتًا '
          'على الخادم. تكون الأسعار المخزنة صالحة عادةً لمدة 12 '
          'ساعة، لكن هذه مدة لحداثة النتائج وليست موعدًا مضمونًا '
          'لحذف البيانات. تُزال السجلات المنتهية عند الوصول إلى '
          'التخزين المؤقت أو تنظيفه.\n\n'
          'قد تحتفظ خدمات الاستضافة بسجلات تشغيل أو وصول تتضمن '
          'معرّفات الشبكة. لم يُتحقق بعد في هذه المسودة من موقع '
          'الاستضافة ومدد الاحتفاظ بسجلاتها ونسخها الاحتياطية. '
          'ويختلف احتفاظ مقدّمي الخدمات عن التخزين داخل التطبيق.',
    ),
    LegalSection(
      id: 'providers',
      title: '6. مقدّمو الخدمات والمعالجة خارج الدولة',
      body:
          'تستخدم الميزات المطلوبة استضافة الخادم وOpenAI للمعالجة '
          'الذكية وSerpAPI للبحث عن المنتجات. قد يعالج هؤلاء '
          'ومقدّمو خدماتهم الفرعيون البيانات خارج دولتك. لا تؤكد '
          'هذه المسودة منطقة استضافة محددة أو آلية نظامية معينة '
          'لنقل البيانات، وعلى المشغّل التحقق من المتطلبات المنطبقة '
          'قبل الإطلاق العام.\n\n'
          'توضح OpenAI أن محتوى API لا يُستخدم للتدريب افتراضيًا '
          'ما لم يوافق العميل اختياريًا على ذلك. وقد تحتفظ بسجلات مراقبة '
          'إساءة الاستخدام لمدة تصل إلى 30 يومًا افتراضيًا، مع '
          'استثناءات نظامية وأمنية. طلب التطبيق عدم تخزين الردود '
          'لا يضمن عدم الاحتفاظ بالبيانات مطلقًا. وتوضح SerpAPI '
          'أن بيانات البحث المعتادة تُحتفظ بها 31 يومًا، وفق '
          'سياستها وشروط الحذف والنسخ الاحتياطي. لا يَعِد التطبيق '
          'بترتيبات خاصة لعدم الاحتفاظ بالبيانات.\n\n'
          'تفاصيل سياسات مقدّمي الخدمات:\n'
          'https://developers.openai.com/api/docs/guides/your-data\n'
          'https://serpapi.com/legal',
    ),
    LegalSection(
      id: 'controls',
      title: '7. خيارات التحكم والحذف',
      body:
          'يمكنك تعديل ملفك الشخصي ومعاملاتك وإدارة جداول التكرار '
          'وحذف المقارنات المحفوظة منفردة ومسح الملخصات الذكية '
          'المعروضة. يزيل خيار مسح البيانات المحفوظة الملف المالي '
          'المحفوظ وسجل الموافقة والسجلات ونسخ الفواتير والجداول والميزانيات '
          'والأهداف وسجل المقارنات من التطبيق. احتفظ بما تحتاجه '
          'من سجلات قبل تأكيد الحذف.\n\n'
          'لا يحذف هذا الإجراء الصور الأصلية في معرض جهازك أو '
          'تفضيلات البحث المحفوظة منفصلة أو نسخ المتصفح والجهاز '
          'الاحتياطية أو ذاكرة الخادم المؤقتة أو سجلات الاستضافة '
          'أو البيانات التي سبق أن استلمها مقدّمو الخدمات. مسح '
          'الملخص يزيل النتيجة المعروضة ولا يحذف تلقائيًا البيانات '
          'التي أُرسلت لإنشائه.\n\n'
          'يمكنك منع الطلبات الاختيارية الجديدة بعدم استخدام '
          'أزرارها، وإلغاء أذونات الكاميرا والصور من إعدادات '
          'الجهاز. لا يؤدي ذلك إلى استرجاع طلب سبق أن عولج.',
    ),
    LegalSection(
      id: 'rights',
      title: '8. حقوق الخصوصية والشكاوى',
      body:
          'قد تشمل حقوقك وفق الأنظمة المنطبقة العلم بالمعالجة '
          'والوصول إلى بياناتك والحصول على نسخة منها وتصحيحها '
          'أو إتلافها، والرجوع عن الموافقة عندما تستند المعالجة '
          'إليها. قد تتطلب الطلبات تحققًا متناسبًا من الهوية '
          'وتخضع للاستثناءات النظامية. يمكنك تقديم شكوى إلى '
          'جهة حماية البيانات المختصة، ومنها سدايا عند انطباق '
          'نظام حماية البيانات الشخصية السعودي.\n\n'
          'يجب استكمال وسيلة استقبال الطلبات لدى المشغّل في '
          'قسم التواصل أعلاه قبل الإطلاق. أدوات الحذف في '
          'التطبيق لا تحل محل حقوقك النظامية أو التزامات المشغّل.',
    ),
    LegalSection(
      id: 'security',
      title: '9. الأذونات وحدود الحماية',
      body:
          'يُستخدم الوصول إلى الكاميرا أو الصور عند اختيارك '
          'صورة، ويمكنك إدارة الأذونات في نظام تشغيل الجهاز. '
          'اختيار الدولة لا يتطلب الوصول إلى GPS. لا يتضمن '
          'كود هذا الإصدار حزمة للإعلانات أو تحليلات الاستخدام. '
          'وللمواقع الخارجية ومقدّمي الخدمات ممارسات مستقلة.\n\n'
          'لا يوفّر الإصدار الحالي حاجز حماية بتسجيل دخول '
          'إلى التطبيق، أو تشفيرًا للسجلات المحفوظة على مستوى '
          'التطبيق. تعتمد حماية الاتصال بالخادم على طريقة '
          'التشغيل، ولا يضمن هذا الإصدار أن الاتصال مشفّر. '
          'احمِ الوصول إلى جهازك وتجنب إرسال تفاصيل حساسة '
          'غير لازمة. ولا تعفي هذه الحدود المشغّل من مسؤوليته '
          'النظامية عن حماية البيانات الشخصية.',
    ),
    LegalSection(
      id: 'children',
      title: '10. الأطفال ومعلومات الآخرين',
      body:
          'تدبير موجّه للبالغين لإدارة أموالهم الشخصية، وليس '
          'مصممًا للأطفال أو لجمع معلوماتهم. لا تقدم معلومات '
          'شخص آخر إلا إذا كانت لديك صلاحية نظامية لذلك، '
          'واحذف التفاصيل التي لا تحتاجها الميزة المطلوبة. '
          'ينبغي الإبلاغ عن أي إرسال غير مناسب مشتبه به '
          'عبر وسيلة التواصل مع المشغّل بعد نشرها.',
    ),
    LegalSection(
      id: 'changes',
      title: '11. تغييرات هذا الإشعار',
      body:
          'يحدد التاريخ أعلاه هذه المسودة. على المشغّل إبقاء '
          'الإشعار متوافقًا مع الميزات والمعالجة الفعلية، '
          'وتوضيح التغييرات الجوهرية قبل تطبيقها والحصول '
          'على أي موافقة جديدة تتطلبها الأنظمة. لا تزيل '
          'التغييرات حقوقًا نظامية. ولا يثبت الإشعار وحده '
          'الامتثال، ولا يسمح باستخدام غير محدود للبيانات، '
          'ولا يحل محل وسائل الحماية التقنية المناسبة.',
    ),
  ],
);

const _termsAr = LegalDocument(
  title: 'شروط الاستخدام',
  introduction:
      'مسودة للمراجعة · آخر تحديث: 29 سبتمبر 2026\n'
      'إصدار المستندات: $currentLegalVersion\n\n'
      'توضح هذه الشروط المقترحة استخدام تدبير لتسجيل المعاملات '
      'المالية الشخصية وإدارة الإنفاق. تُقرأ مع إشعار الخصوصية، '
      'وتحتاج إلى مراجعة وفق الأنظمة المنطبقة على المشغّل '
      'واستكمال البيانات أدناه قبل اعتمادها نهائيًا. عرض هذه '
      'المسودة لا يسجّل موافقتك عليها. تحديد مربع الموافقة والضغط '
      'على ابدأ الآن أو متابعة يحفظ موافقتك على هذا الإصدار على هذا '
      'الجهاز. ولا يمثل هذا السجل تحققًا من الهوية أو موافقة على '
      'معالجة البيانات لأغراض أخرى.',
  sections: [
    _operatorAr,
    LegalSection(
      id: 'scope',
      title: '1. الغرض من التطبيق وأهلية الاستخدام',
      body:
          'يساعدك تدبير على تسجيل الدخل والمصروفات وتخطيط '
          'الميزانيات ومراجعة الإنفاق ومسح الفواتير وإنشاء '
          'ملخصات ذكية ومقارنة عروض تسوق مختارة. وهو موجّه '
          'للبالغين ممن لديهم الأهلية النظامية للموافقة على '
          'الشروط، وللاستخدام الشخصي المشروع.\n\n'
          'لا يحتفظ التطبيق بأموال، ولا يفتح حسابًا بنكيًا، '
          'ولا ينفذ مدفوعات أو يمنح ائتمانًا أو يدير استثمارات. '
          'اسم الملف الشخصي مخصص للعرض، ولا يثبت الهوية '
          'ولا ينشئ علاقة مصرفية.',
    ),
    LegalSection(
      id: 'records',
      title: '2. سجلاتك وإعداداتك',
      body:
          'أدخل معلومات صحيحة وراجع المبالغ والتواريخ '
          'والتصنيفات والتجار قبل الحفظ. تعتمد الإجماليات '
          'والرسوم على السجلات التي تقدمها، ولا تمثل أرصدة '
          'بنكية تم التحقق منها بصورة مستقلة. احتفظ خارج '
          'التطبيق بالفواتير الأصلية والسجلات اللازمة للأغراض '
          'الضريبية أو المحاسبية أو النظامية.\n\n'
          'تغيير عملة الحساب يغيّر وحدة عرض الأرقام نفسها '
          'ولا يحوّلها بسعر صرف. تحقق من عملة العروض الخارجية '
          'بشكل مستقل. المعاملات المتكررة والمجدولة سجلات '
          'مالية، وليست تحويلات بنكية أو سداد فواتير أو '
          'إثباتًا للوفاء بالتزام.',
    ),
    LegalSection(
      id: 'ai',
      title: '3. نتائج الذكاء الاصطناعي والمعلومات المالية',
      body:
          'قد يكون استخراج الفواتير والملخصات الذكية غير '
          'مكتمل أو غير دقيق أو غير مناسب لظروفك. راجع '
          'التفاصيل المستخرجة وتعامل مع التوصيات كاقتراحات '
          'اختيارية للميزانية. لا يوجد ضمان لتحقيق توفير '
          'محدد أو نتيجة مالية أو مستوى معين من الدقة.\n\n'
          'لا يحل التطبيق محل المشورة من مختص مالي أو '
          'ضريبي أو محاسبي أو قانوني مؤهل. اطلب المشورة '
          'المناسبة قبل اتخاذ قرارات ذات آثار مهمة. ولا '
          'تعفي حدود الذكاء الاصطناعي المشغّل من التزاماته '
          'التي تفرضها الأنظمة.',
    ),
    LegalSection(
      id: 'offers',
      title: '4. مقارنة العروض والمتاجر',
      body:
          'تعكس نتائج البحث بيانات مقدّم الخدمة المتاحة، '
          'وقد تتضمن أحجامًا أو طرازات أو حالات أو بائعين '
          'مختلفين. الفرز حسب السعر المعروض لا يضمن أقل '
          'تكلفة إجمالية أو تغطية جميع المتاجر. وقد تكون '
          'العروض المخزنة مؤقتًا قديمة. تحقق لدى المتجر '
          'من العملة والتوفر والأصالة والشحن والضرائب '
          'والإرجاع والسعر النهائي.\n\n'
          'عرض منتج أو صورة أو أيقونة متجر ليس تزكية أو '
          'ضمانًا. تتم عمليات الشراء والدفع والتسليم '
          'والاسترداد والضمان مع البائع الخارجي وفق شروطه. '
          'لا يتلقى تدبير ثمن مشترياتك ولا يقوم بدور البائع، '
          'مع بقاء مسؤوليته عن تصرفاته بالقدر الذي تقرره الأنظمة.',
    ),
    LegalSection(
      id: 'acceptable-use',
      title: '5. الاستخدام المقبول',
      body:
          'استخدم التطبيق لأغراض مشروعة فقط، وقدّم مواد '
          'تملكها أو لديك إذن بمعالجتها. لا ترفع برمجيات '
          'ضارة، ولا تنتحل هوية الآخرين، ولا تنتهك الخصوصية '
          'أو الملكية الفكرية، ولا تحاول الدخول دون تصريح '
          'أو تجاوز ضوابط الوصول أو إرهاق الخدمة بطلبات '
          'آلية مسيئة.\n\n'
          'لا تمنع هذه الشروط الإبلاغ الأمني المشروع أو '
          'التوافق التشغيلي أو الأنشطة الأخرى التي تحميها '
          'الأنظمة المنطبقة.',
    ),
    LegalSection(
      id: 'ownership',
      title: '6. محتواك والملكية الفكرية',
      body:
          'تحتفظ بحقوقك في سجلاتك المالية والمواد التي '
          'ترفعها. تقديم المحتوى لميزة مطلوبة يسمح فقط '
          'بالمعالجة اللازمة لتقديمها، وفق إشعار الخصوصية '
          'والأنظمة المنطبقة، ولا ينقل ملكية محتواك إلى المشغّل.\n\n'
          'تظل برمجيات التطبيق وعلاماته وأسماء وصور '
          'وشعارات ومواد الأطراف الأخرى خاضعة لحقوق '
          'أصحابها والتراخيص مفتوحة المصدر المنطبقة. '
          'الوصول إلى التطبيق لا يمنحك ملكية تلك المواد. '
          'ولا يوجد وعد بحقوق حصرية في المخرجات التي '
          'ينشئها الذكاء الاصطناعي.',
    ),
    LegalSection(
      id: 'availability',
      title: '7. التوفر والتغييرات والرسوم',
      body:
          'تعتمد الميزات على جهازك والاتصال وخدمات '
          'الأطراف الأخرى، وقد تتعطل أثناء الأعطال أو '
          'الصيانة. لا يوجد وعد بتشغيل متواصل أو استعادة '
          'كل سجل. احتفظ بنسخ مستقلة من المعلومات المهمة.\n\n'
          'لا يتضمن التطبيق الحالي عملية دفع لشراء اشتراك '
          'في تدبير. يجب توضيح سعر أي ميزة مدفوعة مستقبلًا '
          'وشروط الفوترة والإلغاء والحصول على الموافقة '
          'اللازمة قبل فرض الرسوم. رسوم بيانات الهاتف '
          'ومشترياتك من المتاجر الخارجية مستقلة عن ذلك.',
    ),
    LegalSection(
      id: 'liability',
      title: '8. المسؤولية وحدودها',
      body:
          'بالقدر الذي تسمح به الأنظمة المنطبقة، تُقدّم '
          'الخدمة ضمن الحدود الموضحة هنا، دون وعد إضافي '
          'بدقة كل نتيجة أو ملاءمتها لكل غرض شخصي. '
          'ولا يسري أي استبعاد للضمانات الضمنية إلا '
          'بالقدر المسموح به نظامًا.\n\n'
          'لا يتحمل المشغّل خسائر تُعزى حصريًا إلى متجر '
          'خارجي أو استخدام مخالف للشروط، إلا حيث تجعله '
          'الأنظمة مسؤولًا. لا تستبعد هذه الشروط المسؤولية '
          'عن الغش أو التصرف العمدي غير المشروع أو الخطأ '
          'الجسيم أو المعالجة غير المشروعة للبيانات الشخصية '
          'أو أي مسؤولية لا يجوز تقييدها نظامًا. لا يوجد '
          'تنازل شامل عن التعويض أو حد صفري للمسؤولية. '
          'وتبقى حقوق المستهلك الإلزامية محفوظة.',
    ),
    LegalSection(
      id: 'ending-use',
      title: '9. إنهاء الاستخدام وإزالة البيانات',
      body:
          'يمكنك التوقف عن استخدام التطبيق في أي وقت '
          'واستخدام أدوات الحذف. راجع إشعار الخصوصية '
          'لمعرفة نطاق مسح البيانات المحفوظة والتعامل '
          'المنفصل مع سجلات مقدّمي الخدمات والتخزين '
          'المؤقت والنسخ الاحتياطية. حذف التطبيق لا '
          'يلغي طلب شراء أو دفعة متكررة فعلية أو التزامًا نظاميًا.\n\n'
          'يجوز تقييد الوصول إلى الميزات المتصلة بالإنترنت '
          'بصورة مشروعة ومتناسبة لمعالجة إساءة الاستخدام '
          'أو الحوادث الأمنية أو المتطلبات النظامية. '
          'ويظل أي تقييد خاضعًا لحقوق المستهلك وحماية '
          'البيانات المنطبقة.',
    ),
    LegalSection(
      id: 'disputes',
      title: '10. الاستفسارات والنزاعات والأنظمة المنطبقة',
      body:
          'يجب استكمال بيانات التواصل الموثقة ودولة '
          'التشغيل في القسم أعلاه. يمكنك السعي إلى حل '
          'ودي عبر وسيلة التواصل عند إتاحتها، لكن ذلك '
          'ليس شرطًا لتقديم شكوى مشروعة أو رفع دعوى.\n\n'
          'تحدد الأنظمة الإلزامية المنطبقة حقوقك والجهة '
          'أو المحكمة المختصة. لا تختار هذه المسودة '
          'محكمة أجنبية حصرية، ولا تفرض التحكيم، ولا '
          'تسقط حقك في اللجوء إلى جهة رقابية أو قضائية '
          'أو طلب الإنصاف. ولا يمكن لأي صياغة أن تضمن '
          'عدم تعرض المشغّل لشكاوى أو إجراءات قضائية.',
    ),
    LegalSection(
      id: 'updates',
      title: '11. التحديثات والتفسير',
      body:
          'ينبغي إشعارك بالتغييرات الجوهرية قبل تطبيقها '
          'وطلب موافقة جديدة حيث تتطلبها الأنظمة. لا '
          'يجوز لإصدار لاحق إسقاط حقوق مكتسبة بأثر '
          'رجعي. إذا تعذر إنفاذ بند، تسري بقية البنود '
          'بالقدر الذي تسمح به الأنظمة.\n\n'
          'تهدف النسختان العربية والإنجليزية إلى بيان '
          'الشروط نفسها. ولا تزيل أي ترجمة حماية '
          'تفرضها الأنظمة المنطبقة. تظل هذه مسودة '
          'تحتاج إلى مراجعة ولا تمثل اعتمادًا قانونيًا للتطبيق.',
    ),
  ],
);
