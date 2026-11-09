import 'package:flutter_test/flutter_test.dart';
import 'package:tra_list/business_intelligence/isher_navigation.dart';

void main() {
  test('recognizes explicit English and Swahili page commands', () {
    expect(parseIsherNavigationCommand('fungua miamala'), IsherDestination.transactions);
    expect(parseIsherNavigationCommand('Fungua ukurasa wa invoice'), IsherDestination.invoices);
    expect(parseIsherNavigationCommand('open receipts'), IsherDestination.receipts);
    expect(parseIsherNavigationCommand('open quotation'), IsherDestination.quotation);
    expect(parseIsherNavigationCommand('fungua ripoti'), IsherDestination.analytics);
    expect(parseIsherNavigationCommand('fungua kazi za wateja'), IsherDestination.jobs);
    expect(parseIsherNavigationCommand('open tasks'), IsherDestination.tasks);
    expect(parseIsherNavigationCommand('fungua wafanyakazi'), IsherDestination.staff);
    expect(parseIsherNavigationCommand('go to POS'), IsherDestination.pos);
    expect(parseIsherNavigationCommand('tafadhali nifungulie page ya miamala'), IsherDestination.transactions);
    expect(parseIsherNavigationCommand('Isher, fungua ukurasa wa invoice tafadhali'), IsherDestination.invoices);
    expect(parseIsherNavigationCommand('unaweza kunifungulia orodha ya risiti?'), IsherDestination.receipts);
    expect(parseIsherNavigationCommand('please open the page of reports'), IsherDestination.analytics);
    expect(parseIsherNavigationCommand('could you open staff?'), IsherDestination.staff);
    expect(parseIsherNavigationCommand('naomba fungua nukuu'), IsherDestination.quotation);
  });

  test('rejects unsupported, ambiguous and non-navigation requests', () {
    expect(parseIsherNavigationCommand('fungua stock'), isNull);
    expect(parseIsherNavigationCommand('open invoices and receipts'), isNull);
    expect(parseIsherNavigationCommand('fungua invoice ya mteja Asha'), isNull);
    expect(parseIsherNavigationCommand('fungua miamala na ufute moja'), isNull);
    expect(parseIsherNavigationCommand('how can I open a business?'), isNull);
    expect(isIsherNavigationCommand('show me sales'), isFalse);
    expect(isIsherNavigationCommand('fungua stock'), isTrue);
  });
}
