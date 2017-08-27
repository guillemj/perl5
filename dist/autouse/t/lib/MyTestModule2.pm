package MyTestModule2;
use warnings;

use Exporter qw(import);
@EXPORT_OK = 'test_function2';

sub test_function2 {
  return 'works';
}

1;
