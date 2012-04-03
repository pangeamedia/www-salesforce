#!/usr/bin/env perl

use strict;
use warnings;

use Test::More tests => 31;

use SOAP::Lite;
use MIME::Base64;

#test -- can we find the module?
BEGIN { use_ok('WWW::Salesforce') }

# skip tests under automated testing or without user and pass
my $automated = $ENV{AUTOMATED_TESTING};
my $skip_reason;
if ($automated) {
    $skip_reason = 'skip live tests under $ENV{AUTOMATED_TESTING}';
}

if ( !$automated && !$ENV{SFDC_USER} && 
     !$ENV{SFDC_PASS} && !$ENV{SFDC_TOKEN} ) {

     $skip_reason = 'set $ENV{SFDC_USER}, $ENV{SFDC_PASS}, $ENV{SFDC_TOKEN}';
}

SKIP: {

    skip $skip_reason, 30, if $skip_reason;

    my $user = $ENV{SFDC_USER};
    my $pass = $ENV{SFDC_PASS} . $ENV{SFDC_TOKEN};

    #test -- new object/connection...
    my $sforce =
      WWW::Salesforce->login( 'username' => $user, 'password' => $pass );
    ok( $sforce, "Login test" ) or BAIL_OUT($!);

    #test -- describeGlobal
    {
        my $res = $sforce->describeGlobal();
        ok( $res, "describeGlobal" ) or diag($!);
    }

    #test -- describeLayout
    {
        my $res = $sforce->describeLayout( 'type' => 'Account' );
        ok( $res, "describeLayout" ) or diag($!);
    }

    #test -- describeSObject
    {
        my $res = $sforce->describeSObject( 'type' => 'Account' );
        ok( $res, "describeSObject" ) or diag($!);
    }

    # tests -- describeTabs
    {
        my $passed = 0;

        #test -- describeTabs
        my $res = $sforce->describeTabs();
        $passed = 1 if ( $res && $res->valueof('//result') );
        ok( $passed, "describeTabs return" ) or diag($!);

      SKIP: {
            skip( "Can't check tabs results since describeTabs failed", 2 )
              unless $passed;
            my @apps = $res->valueof('//result');
            ok( $#apps > 1,                  "list of tab sets" );
            ok( defined $apps[0]->{'label'}, "app has a label" );
        }
    }

    #test -- getServerTimestamp
    {
        my $res = $sforce->getServerTimestamp();
        ok( $res, "getServerTimestamp" ) or diag($!);
    }

    #test -- getUserinfo
    {
        my $res = $sforce->getUserInfo();
        ok( $res, "getUserInfo" ) or diag($!);
    }

    #test -- query
    {
        my $res =
          $sforce->query( 'query' => 'select id from account', 'limit' => 5 );
        ok( $res, "query accounts" ) or diag($!);

        #test -- queryMore
      SKIP: {
            my $locator = $res->valueof('//queryResponse/result/queryLocator')
              if $res;
            skip( "No more results to queryMore for", 1 ) unless $locator;
            $res =
              $sforce->queryMore( 'queryLocator' => $locator, 'limit' => 5 );
            ok( $res, "queryMore accounts" ) or diag($!);
        }
    }

    #test -- queryAll
    {
        my $res =
          $sforce->queryAll( 'query' => 'select id from account', 'limit' => 5 );
        ok( $res, "queryAll accounts" ) or diag($!);

        #test -- queryMore against queryAll
      SKIP: {
            my $locator = $res->valueof('//queryAllResponse/result/queryLocator')
              if $res;
            skip( "No more results to queryMore for", 1 ) unless $locator;
            $res =
              $sforce->queryMore( 'queryLocator' => $locator, 'limit' => 5 );
            ok( $res, "queryMore all accounts" ) or diag($!);
        }
    }

    # test -- relation query
    {
        my $res = $sforce->query( 'query' =>
              'Select a.CreatedBy.Username, a.Name From Account a limit 2' );
        my $passed = 0;
        $passed = 1
          if ( $res
            && $res->valueof('//done') eq 'true'
            && $res->valueof('//size') eq '2'
            && $res->valueof('//records') );
        ok( $passed, "relational query" ) or diag($!);

        my @recs;
        @recs = $res->valueof('//records') if $passed;

        # test -- check expected structure of the relation query
        ok(
            defined( $recs[0]->{'Name'} )
              && defined( $recs[0]->{'CreatedBy'}->{'Username'} ),
            "relational query - first record check"
        );

        # test -- second check for expected structure
        ok(
            defined( $recs[1]->{'Name'} )
              && defined( $recs[1]->{'CreatedBy'}->{'Username'} ),
            "relational query - second record check"
        );
    }

    # test -- create an account
    {
        my $res = $sforce->create(
            'type' => 'Account',
            'Name' => 'foobar test account'
        );
        my $passed = 0;
        $passed = 1
          if ( $res
            && $res->valueof('//success') eq 'true'
            && defined( $res->valueof('//id') ) );
        ok( $passed, "create an account" ) or diag($!);

      SKIP: {
            skip(
                "can't update and delete new account since the creation failed",
                2
            ) unless $passed;

            #test -- update
            my $id = 0;
            $id = $res->valueof('//id') if $passed;
            $res = $sforce->update(
                'type' => 'Account',
                'id'   => $id,
                'Name' => 'foobar test account updated'
            );
            $passed = 0;
            $passed = 1
              if ( $res->valueof('//success') eq 'true'
                && defined( $res->valueof('//id') ) );
            ok( $passed, "update account created" ) or diag($!);

            # test -- delete the account we just created and updated
            my @toDel = ($id);
            $res = $sforce->delete(@toDel);
            ok(
                $res->valueof('//success') eq 'true'
                  && defined( $res->valueof('//id') ),
                "delete account created"
            );
        }
    }

    # test -- create a lead (with an ampersand)
    if (0) {
        my $res = $sforce->create(
            'type' => 'Lead',
            'Email' => 'foo@example.com',
            'FirstName' => 'foobar',
            'LastName' => 'test lead',
            'Company' => 'Foo & Bar',
        );
        my $passed = 0;
        $passed = 1
          if ( $res
            && $res->valueof('//success') eq 'true'
            && defined( $res->valueof('//id') ) );
        ok( $passed, "create a lead, with ampersand" ) or diag($!);

      SKIP: {
            skip(
                "can't update and delete new lead since the creation failed",
                2
            ) unless $passed;

            #test -- update
            my $id = 0;
            $id = $res->valueof('//id') if $passed;
            $res = $sforce->update(
                'type' => 'Lead',
                'id'   => $id,
                'Name' => 'foobar test lead updated'
            );
            $passed = 0;
            $passed = 1
              if ( $res->valueof('//success') eq 'true'
                && defined( $res->valueof('//id') ) );
            ok( $passed, "update lead created" ) or diag($!);

            # test -- delete the lead we just created and updated
            my @toDel = ($id);
            $res = $sforce->delete(@toDel);
            ok(
                $res->valueof('//success') eq 'true'
                  && defined( $res->valueof('//id') ),
                "delete lead created"
            );
        }
    }

    # tests -- base64 doc files
    {
        my $passed = 0;
        my $fid    = 0;
        my $docid  = 0;
        my $doc    = 0;

        # graphic (png) in an unpacked hex string; pack to binary
        my $image = pack 'h*',
'9805e474d0a0a1a0000000d094844425000000cf000000e38020000000089e1ef800000090078495370000e04c0000e04c1059b2e0b1000000704794d454706db0e030c161f895545e000000704754854714574786f627009aeacc84000000c047548547445637362796074796f6e60031901232000000a04754854734f60797279676864700caf0cca3000000e047548547342756164796f6e6024796d65600537ff090000000904754854735f666477716275600d507ffa3000000b04754854744963736c61696d65627007b0c4bf80000008047548547751627e696e676000cb16e78000000704754854735f657273656005fff38be000000804754854734f6d6d656e647006fcc69fb0000006047548547459647c656008aee2d72000010009444144587c9ded9d4abba82016813fcd5d407d17b7307433fee5888b08ed2cd97bcd514fcb77029de8d30532f350a2a98e19fed152740929af4c2a0cc9cabea36004a4cde8630008f4301d384e088e1427044f029302a709c101d384e088e14274f2a7956695927f933aaa3fcc22fa51b1ad97d7c712b4ba0d9602ea46fae4a9e2b7d0bf5befd58739b0abeab65076c813e2ade6b13c98ca3353586dc95d8c853a7a8663a10f60c0be7f7b0dc3d35e50dab8ec8df3f1067771cd8135fb5a26c81352f7f691b655d97e24136c54bd656b49d417f4c359ed4e3f976b1ce91bb37ad2fd982a1746f61cba698b7325267771cd89ca5c025352ae8e7478aaf1df96871f548988739ad100000100094441445cba694ddb97d37fbfb5506fd899fb730c27e625a62473ebca16c7a5400e555eafd875de8ed4e2a5836df41597e16906537337077957cd4727a035498cd735d0adf636c8666c4408136c46935f52fbfdf8435ea4cdc2d874606f64892edc501ffa20e8b518a7e35bf680176f2e667756c506fec034d764ece4342faa97d87e1cc649b90db1e89170c83db97e33f6a322f385a47c288e4689fd8ad4482664a33e95ac5493e3f6fee2a2471071019a188a4a09f2f33c289b0d0563ace3647b0543e415ab95baa37a3520ec5bfc42557c69bf30fa2cb2ab0d2bd72bab51c3c7227a346a2cdf94dde8f1aacba0aed831e6ab8ab0815db71991bf0f3d79432247d3e6f8ce7b3b500001000944414450f07cdc30c93f9c2e5e7319e7991bb290faa76925755f12d2af1fc33377f87ee8965072ad7ac633e2f24b64075271032f2e2a7d9a203edf28e5d098e5faa65b2a75b047e50a6995dc832e7b07aa3a7b33df571e86f113458fb798171d67da0e45532745f0f82a715714fbd01ce4726476ce975d6849f184decc1a7e0fdc91407e133b3e2a82c7fd6952e65b254faf24c5ef7da19e7ebcb9ea3522fc2755dcd49759a768b005c56c503e68333d08d091b76382fd7e63d3b07722cc4f3d28b8f50566bc203b6b081378395d1bd79e69b7d7c96562f87e37e287de2b4b398ebe45f4849b79e31f4fed27f3d96032b98a7ae06fbb5a79f2749552dbb8d2adcf5784b253106bb0000100094441445984efd779cb2ed503d6d26ef5589aaf57be45e392bf7a6f7d1c3350adabcd66b74813f975c9817201d96f27fc58a2a9eab6eb639587e1659b0e6a5673da72ddac57aa0d00eeb467d7f5c88963a224e5bd8036c20d9c6f06f470192bc1ddc718d4f11fe28b91736c6a57aa0e3a14b1b82e66d3f94c3141b1cae8043ac0133c57557d29e91b9aaf12fe54836c155f49540a7b50e9887bab0cc737a6bd476795e66a8aec8b9c64fd3ecb4a3cda8d388b1e9a7166631aae78054e8812bcc555d63dcf3af86fa4c3c86ffc4376529fc9b0ca7d50d99ecea4fc9c2d33d80557ff4d8f8e60290d33fcc97db67773714ce6052033e865227deac55d9762b85413db9bfb6783ce3e70000100094441445cf8c2371a8a4dc9c23b295fdbae486ff0f93f6c0d5dab316ff71a1ec9e20724f7738fe50bac21ed9c03c1d9d57ee0ca658765f1cea54c25d87e817ec7ad0e91879392461af3b9eb8757fcd3340710f8e5ba4f770867c84b59a1384b3bd54d50398e76640e0b2fb922cdbb44d6f95bc587fd41a169b1d76e1d59c3679b5161c22c3950dbb976284cd30f20d9c18461c85b4f63ded7a36ff5face20764afbe27ef7f17f2fc94c508f900109c101d384e088e14274242a73f7e640c10c94c509e88eda488f91f7367eaec96c5070d40af3b873f38bdf75dd0c23ec4e28ca3cffc9209819e487300c0044f029302a709c101d384e088e1427044f029302a709c101dce9dbb2e000000d694441445384e088e1427044f029302a709c101d384e088e1427044f029302a709c101d384e8f174b1000cbd9c2bcaff0dfb2358737a04244fae74873029302a709c101d384e84826a71fbefd3ad4007039df7f73b4d2b732efcf974b900e842bfbef0680f60428044f0293ef70c649da16b5ad25bc000000009454e444ea240628';

        #test -- do the first query
        my $res = $sforce->query(
            'type'  => 'Document',
            'query' => "select id from Folder where Type = 'Document' "
        );
        $passed = 1 if ( $res && defined( $res->valueof('//records') ) );
        ok( $passed, "query for 'Document' folder id" ) or diag($!);

        #test -- get folder id
      SKIP: {
            skip( "Can't get folder ID since the query failed", 1 )
              unless $passed;

            # get the folder id and create an image body
            my ($folder) = $res->valueof('//records');
            $fid = $folder->{'Id'}[0];
            ok( $fid, "grab folder ID from previous query" )
              or diag("Invalid folder ID");
        }

        #test -- create png document using above binary image
      SKIP: {
            skip( "Can't create a document since I can't get the folder ID", 1 )
              unless $fid;

            # create a new document using a b64 string
            $res = $sforce->create(
                'type'        => 'Document',
                'Name'        => 'imagetest.png',
                'Body'        => $image,
                'FolderId'    => $fid,
                'ContentType' => 'image/png',
                'Type'        => 'png',
                'IsPublic'    => 'true',
            );
            $docid = $res->valueof('//id')
              if ( $res && $res->valueof('//success') eq 'true' );
            ok( $docid, "create new png document" ) or diag($!);
        }

        #test -- query for the document ID
      SKIP: {
            skip(
"Can't query for the document we just tried to create because we couldn't determine the ID",
                1
            ) unless $docid;
            $res = $sforce->query(
                'type' => 'Document',
                'query' =>
                  "select id,body from Document where Id = '$docid' limit 1"
            );
            $doc = $res->valueof('//records')
              if ( defined( $res->valueof('//records') )
                && $res->valueof('//size') eq '1' );
            ok( $doc, "query for document we just created" ) or diag($!);
        }

        #test -- compare returned doc with original
      SKIP: {
            skip( "Can't compare doc because we couldn't query it", 1 )
              unless $doc;
            ok( $doc->{'Body'} eq encode_base64($image, ''),
                "compare document with original" );
        }

        # test -- delete that image
      SKIP: {
            skip( "Can't delete image because it wasn't created properly", 1 )
              unless $docid;
            my @toDel = ($docid);
            $res = $sforce->delete(@toDel);
            ok( $res && $res->valueof('//success') eq 'true',
                "delete created image" )
              or diag($!);
        }
    }

    #tests -- create and mass update some contacts
    {
        my $oneid  = 0;
        my $twoid  = 0;
        my $passed = 0;

        #test -- create an account
        my $res =
          $sforce->create( 'type' => 'Contact', 'LastName' => 'thing1' );
        $oneid = $res->valueof('//id') if $res;
        ok( $oneid, "multi-update - create first account to test against" )
          or diag($!);

        #test -- create another account
      SKIP: {
            skip( "No point creating a second account since the first failed",
                1 )
              unless $oneid;
            $res =
              $sforce->create( 'type' => 'Contact', 'LastName' => 'thing2' );
            $twoid = $res->valueof('//id') if $res;
            ok( $twoid, "multi-update - create second account to test against" )
              or diag($!);
        }

        #test -- update the two accounts above
      SKIP: {
            skip(
"No point trying a multiple update since we couldn't create multiple contacts",
                1
            ) unless $oneid && $twoid;
            $res = $sforce->update(
                type => 'Contact',
                { id => $oneid, 'LastName' => 'thing3' },
                { id => $twoid, 'LastName' => 'thing4' }
            );
            $passed = 1 if ( $res && $res->valueof('//success') eq 'true' );
            ok( $passed, "multi-update batch contacts" ) or diag($!);
        }

        #test -- check the result set of the update above
      SKIP: {
            skip( "No results to check value of", 1 ) unless $passed;
            my @results = $res->valueof('//result');
            ok(
                defined( $results[0] )
                  && defined( $results[1] )
                  && $#results == 1,
                "multi-update batch results check"
            );
        }

        #test -- cleanup the temp contact records
      SKIP: {
            skip( "no results to delete from the mult-update batch", 1 )
              unless ( $oneid || $twoid );
            if ( $oneid && $twoid ) {
                $res = $sforce->delete( $oneid, $twoid );
            }
            elsif ($oneid) {
                $res = $sforce->delete($oneid);
            }
            else {
                $res = $sforce->delete($twoid);
            }
            ok( $res && $res->valueof('//success') eq 'true',
                "multi-update batch deletion" )
              or diag($!);
        }
    }

    # for debug, dump return values
    #use Data::Dumper;
    #print STDERR Dumper($res->valueof('//result'));

}

