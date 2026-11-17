# frozen_string_literal: true

module KeyboardShortcutHelpers
  def press_save_shortcut
    press_ctrl_shift('s')
  end

  def press_close_shortcut
    press_ctrl_shift('x')
  end

  # Presses Shift+Ctrl+X where it should do nothing, then verifies the page
  # neither navigated nor reloaded. This records two signals in the page:
  # - navigation-started: set when a navigation begins. The Navigation API's
  #   navigate event fires synchronously when the shortcut assigns
  #   window.location.href; beforeunload is the fallback for browsers
  #   without it.
  # - close-shortcut-handled: set by a keydown listener added after the
  #   app's shortcut handler, so it runs once the handler has finished.
  def press_close_shortcut_and_expect_nothing
    url = page.current_url
    page.execute_script(<<~JS)
      const markNavigationStarted = function () {
        document.body.classList.add('navigation-started');
      };
      if (window.navigation) {
        window.navigation.addEventListener('navigate', markNavigationStarted);
      } else {
        window.addEventListener('beforeunload', markNavigationStarted);
      }

      window.addEventListener('keydown', function (event) {
        if (event.ctrlKey && event.shiftKey && event.key.toLowerCase() === 'x') {
          document.body.classList.add('close-shortcut-handled');
        }
      });
    JS

    press_close_shortcut

    expect(page).to have_css('body.close-shortcut-handled')
    aggregate_failures do
      expect(page).to have_no_css('body.navigation-started')
      expect(page).to have_current_path(url, url: true)
    end
  end

  # TEMPORARY DIAGNOSTICS (ANW-3137): records what happens around a close
  # shortcut keypress on Infinite Tree pages, to find why it sometimes
  # doesn't navigate in CI. Entries go to sessionStorage so they survive the
  # navigation and can be printed whether or not the example passes.
  # Remove together with print_close_shortcut_diagnostics.
  def install_close_shortcut_diagnostics
    page.execute_script(<<~JS)
      (function () {
        var KEY = 'closeShortcutDiagnostics';
        sessionStorage.setItem(KEY, '[]');

        var log = function (message) {
          var entries = JSON.parse(sessionStorage.getItem(KEY) || '[]');
          entries.push(new Date().toISOString().slice(11, 23) + ' ' + message);
          sessionStorage.setItem(KEY, JSON.stringify(entries));
        };

        var describe = function (el) {
          if (!el) return 'none';
          var name = el.tagName.toLowerCase();
          if (el.id) name += '#' + el.id;
          if (typeof el.className === 'string' && el.className.trim()) {
            name += '.' + el.className.trim().split(/\\s+/).join('.');
          }
          return name;
        };

        var pane = document.querySelector('#infinite-tree-record-pane');
        var tree = document.querySelector('#infinite-tree-component');

        var state = function () {
          return 'href=' + location.href +
            ' paneBlocked=' + (pane ? pane.classList.contains('blocked') : 'no-pane') +
            ' paneForm=' + describe(pane && pane.querySelector('form.aspace-record-form')) +
            ' firstRecordForm=' + describe(document.querySelector('form.aspace-record-form')) +
            ' modalShown=' + !!document.querySelector('.modal.show') +
            ' active=' + describe(document.activeElement) +
            ' treeReadonlyPath=' + (tree ? tree.dataset.readonlyPath : 'no-tree');
        };

        log('installed ' + state());

        var isCloseKey = function (event) {
          return event.ctrlKey && event.shiftKey && event.key.toLowerCase() === 'x';
        };

        window.addEventListener('keydown', function (event) {
          if (isCloseKey(event)) {
            log('keydown before app handler: which=' + event.which + ' target=' + describe(event.target) + ' ' + state());
          }
        }, true);

        window.addEventListener('keydown', function (event) {
          if (isCloseKey(event)) {
            log('keydown after app handler: defaultPrevented=' + event.defaultPrevented + ' ' + state());
          }
        });

        var originalClose = AS.closeRecordForm;
        AS.closeRecordForm = function () {
          log('AS.closeRecordForm called ' + state());
          var result = originalClose.apply(this, arguments);
          log('AS.closeRecordForm returned href=' + location.href);
          return result;
        };

        if (window.navigation) {
          window.navigation.addEventListener('navigate', function (event) {
            log('navigate: type=' + event.navigationType + ' hashChange=' + event.hashChange +
              ' destination=' + event.destination.url);
          });
          window.navigation.addEventListener('navigatesuccess', function () {
            log('navigatesuccess href=' + location.href);
          });
          window.navigation.addEventListener('navigateerror', function (event) {
            log('navigateerror: ' + event.message);
          });
        } else {
          log('no Navigation API');
        }

        window.addEventListener('hashchange', function (event) {
          log('hashchange: ' + event.oldURL + ' -> ' + event.newURL);
        });
        window.addEventListener('beforeunload', function () { log('beforeunload'); });
        window.addEventListener('pagehide', function () { log('pagehide'); });

        if (pane) {
          new MutationObserver(function (mutations) {
            mutations.forEach(function (mutation) {
              if (mutation.type === 'attributes') {
                log('pane class=' + pane.className);
              } else {
                log('pane content replaced: form=' + describe(pane.querySelector('form.aspace-record-form')));
              }
            });
          }).observe(pane, { attributes: true, attributeFilter: ['class'], childList: true });
        }
      })();
    JS
  end

  # TEMPORARY DIAGNOSTICS (ANW-3137): see install_close_shortcut_diagnostics.
  def print_close_shortcut_diagnostics
    entries = page.evaluate_script("sessionStorage.getItem('closeShortcutDiagnostics')")
    lines = entries ? JSON.parse(entries) : ['(no entries)']
    $stdout.puts "\n=== Close shortcut diagnostics: #{RSpec.current_example.full_description} ==="
    lines.each { |line| $stdout.puts "  #{line}" }
    $stdout.puts "  final href=#{page.current_url}"
    $stdout.puts "=== end ===\n"
  rescue StandardError => e
    $stdout.puts "Close shortcut diagnostics unavailable: #{e.class}: #{e.message}"
  end

  def press_ctrl_shift(key)
    page.driver.browser.action
      .key_down(:control).key_down(:shift).send_keys(key)
      .key_up(:shift).key_up(:control).perform
  end

  def start_counting_form_submissions
    page.execute_script(<<~JS)
      window.formSubmissionCount = 0;
      document.addEventListener('submit', function () { window.formSubmissionCount += 1; }, true);
    JS
  end

  def form_submission_count
    page.evaluate_script('window.formSubmissionCount')
  end
end
