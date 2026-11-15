/// HTML fixtures for the OALD lookup tool.
///
/// **These are trimmed copies of the live site's markup, not invented page
/// shapes.** On 2026-11-15 the app's own HTTP stack fetched
/// `/definition/english/{observe,happy,take-off_1}` and the pages were inspected;
/// the saved full pages are in the control workspace under
/// `.work/oald-evidence/` and the key selectors are quoted in
/// `oald_parser.dart`'s library comment and in `OALD-TOOL-2026-11-15.md`.
/// Each fixture keeps the structure the parser reads (entry, header, phonetics,
/// `ol.senses_multiple` / `li.sense`, `ul.examples`, `.collapse` boxes,
/// `span.pv-g`, `div.idioms`, `unbox="wordfamily"`) and shortens the prose so a
/// test failure is readable.
///
/// They deliberately include the traps the live pages contain:
///
///  * verb-form pronunciations inside `.collapse` (must not become the
///    headword's pronunciation);
///  * Extra Examples inside `.collapse` (omitted, not mixed into main examples);
///  * idioms and unrelated phrasal verbs as separate groups (not main senses);
///  * a Word Family box with `.wfw` / `.wfp` / `.wfo` but no links.
library;

/// `observe`: four senses, labelled pronunciations, patterns, labels, and both
/// traps (verb forms, extra examples).
const String oaldObservePage = '''
<!doctype html>
<html>
<head><title>observe verb - Definition, pictures, pronunciation and usage notes | Oxford Advanced Learner&apos;s Dictionary at OxfordLearnersDictionaries.com</title></head>
<body>
  <div class="responsive_container xenglish">
    <div id="entryContent" class="oald">
      <div class="entry" id="observe">
        <div class="top-container">
          <div class="top-g">
            <div class="webtop">
              <h1 class="headword">observe</h1>
              <span class="pos">verb</span>
              <span class="phonetics">
                <div class="phons_br" geo="br">
                  <div class="sound audio_play_button" data-src-mp3="https://www.oxfordlearnersdictionaries.com/media/observe__gb_2.mp3" data-src-ogg="https://www.oxfordlearnersdictionaries.com/media/observe__gb_2.ogg"></div>
                  <span class="phon">/əbˈzɜːv/</span>
                </div>
                <div class="phons_n_am" geo="n_am">
                  <div class="sound audio_play_button" data-src-ogg="https://www.oxfordlearnersdictionaries.com/media/observe__us_1.ogg"></div>
                  <span class="phon">/əbˈzɜːrv/</span>
                </div>
              </span>
              <div class="collapse">
                <span class="unbox" unbox="verbforms">
                  <span class="box_title">Verb Forms</span>
                  <span class="body"><table class="verb_forms_table"><tr class="verb_form">
                    <td class="verb_form"><span class="vf_prefix">past simple</span> observed</td>
                    <td><span class="phonetics"><div class="phons_br"><span class="phon">/WRONG-VERB-FORM/</span></div></span></td>
                  </tr></table></span>
                </span>
              </div>
            </div>
          </div>
        </div>
        <ol class="senses_multiple">
          <li class="sense" sensenum="1" id="observe_sng_1">
            <span class="sensetop"><span class="grammar">[transitive]</span></span>
            <span class="labels">(formal)</span>
            <span class="cf">observe somebody/something</span>
            <span class="def">to see or notice somebody/something</span>
            <ul class="examples">
              <li><span class="x">I observed a light in the distance.</span></li>
            </ul>
            <div class="collapse"><span class="unbox" unbox="extra_examples"><span class="box_title">Extra Examples</span><ul class="examples"><li><span class="unx">She was unaware that she was being observed from the window.</span></li></ul></span></div>
          </li>
          <li class="sense" sensenum="2" id="observe_sng_2">
            <span class="sensetop"><span class="grammar">[transitive, intransitive]</span></span>
            <span class="def">to watch somebody/something carefully, especially to learn more about them</span>
            <ul class="examples">
              <li><span class="x">The police observed the crowd closely.</span></li>
              <li><span class="x">Scientists observed the animals for hours.</span></li>
            </ul>
          </li>
          <li class="sense" sensenum="3" id="observe_sng_3">
            <span class="sensetop"><span class="grammar">[transitive]</span></span>
            <span class="cf">observe that…</span>
            <span class="cf">+ speech</span>
            <span class="labels">(formal)</span>
            <span class="def">to make a remark</span>
            <ul class="examples">
              <li><span class="x">She observed that it was getting late.</span></li>
            </ul>
          </li>
          <li class="sense" sensenum="4" id="observe_sng_4">
            <span class="sensetop"><span class="grammar">[transitive]</span></span>
            <span class="def">to obey rules, laws, etc.</span>
            <ul class="examples">
              <li><span class="x">Will the rebels observe the ceasefire?</span></li>
              <li><span class="x">All drivers must observe the speed limit.</span></li>
            </ul>
          </li>
        </ol>
      </div>
    </div>
  </div>
</body>
</html>''';

/// `happy`: sense groups (`shcut-g` / `shcut`), a real Word Family box, and an
/// idioms block that must not be counted as main senses.
const String oaldHappyPage = '''
<!doctype html>
<html>
<head><title>happy adjective - Definition, pictures, pronunciation and usage notes | Oxford Advanced Learner&apos;s Dictionary</title></head>
<body>
  <div id="entryContent" class="oald">
    <div class="entry" id="happy">
      <div class="top-container">
        <div class="top-g">
          <div class="webtop">
            <h1 class="headword">happy</h1>
            <span class="pos">adjective</span>
            <span class="phonetics">
              <div class="phons_br" geo="br"><span class="phon">/ˈhæpi/</span></div>
              <div class="phons_n_am" geo="n_am"><span class="phon">/ˈhæpi/</span></div>
            </span>
            <div class="inflections">(comparative <span class="inflected_form">happier</span>, superlative <span class="inflected_form">happiest</span>)</div>
            <div class="collapse">
              <span class="unbox" unbox="wordfamily">
                <span class="box_title">Word Family</span>
                <span class="body">
                  <ul class="ul">
                    <li class="li"><span class="p"><span class="wfw">happy</span> <span class="wfp" wfp="adj">adjective</span> <span class="wfo">(≠ unhappy)</span></span></li>
                    <li class="li"><span class="p"><span class="wfw">happily</span> <span class="wfp" wfp="adv">adverb</span> <span class="wfo">(≠ unhappily)</span></span></li>
                    <li class="li"><span class="p"><span class="wfw">happiness</span> <span class="wfp" wfp="n">noun</span> <span class="wfo">(≠ unhappiness)</span></span></li>
                  </ul>
                </span>
              </span>
            </div>
          </div>
        </div>
      </div>
      <ol class="senses_multiple">
        <span class="shcut-g">
          <h2 class="shcut">feeling/giving pleasure</h2>
          <li class="sense" sensenum="1" id="happy_sng_1">
            <span class="def">feeling or showing pleasure; pleased</span>
            <ul class="examples"><li><span class="x">a happy family</span></li></ul>
          </li>
          <li class="sense" sensenum="2" id="happy_sng_2">
            <span class="def">giving or causing pleasure</span>
          </li>
        </span>
        <span class="shcut-g">
          <h2 class="shcut">at celebration</h2>
          <li class="sense" sensenum="3" id="happy_sng_3">
            <span class="def">if you wish somebody a Happy Birthday, Happy New Year, etc. you mean that you hope they have a pleasant celebration</span>
          </li>
        </span>
      </ol>
      <div class="idioms">
        <span class="idm-g">
          <div class="top-container"><div class="top-g"><div class="webtop"><span class="idm">happy as a sandboy</span></div></div></div>
          <ol class="sense_single">
            <li class="sense" id="happy_sng_9"><span class="def">very happy</span></li>
          </ol>
        </span>
      </div>
    </div>
  </div>
</body>
</html>''';

/// `take off`: a phrasal-verb page. The page's own header is `take off`; the
/// `.pv-g` groups list several phrasal verbs of `take`, so only the matching
/// group's senses may be returned.
const String oaldTakeOffPage = '''
<!doctype html>
<html>
<head><title>take off phrasal verb - Definition, pictures, pronunciation and usage notes | Oxford Advanced Learner&apos;s Dictionary</title></head>
<body>
  <div id="entryContent" class="oald">
    <div class="entry" id="take-off_1">
      <div class="top-container">
        <div class="top-g">
          <div class="webtop">
            <h1 class="headword">take off</h1>
            <span class="pos">phrasal verb</span>
          </div>
        </div>
      </div>
      <span class="pv-g" id="take_pvg_14">
        <div class="top-container"><div class="top-g"><div class="webtop"><span class="pv">take off</span></div></div></div>
        <ol class="senses_multiple">
          <li class="sense" sensenum="1" id="take_sng_165">
            <span class="def">to leave the ground and begin to fly</span>
            <ul class="examples"><li><span class="x">The plane took off an hour late.</span></li></ul>
          </li>
          <li class="sense" sensenum="2" id="take_sng_166">
            <span class="def">to leave a place, especially in a hurry</span>
          </li>
        </ol>
      </span>
      <span class="pv-g" id="take_pvg_15">
        <div class="top-container"><div class="top-g"><div class="webtop"><span class="pv">take after</span></div></div></div>
        <ol class="senses_multiple">
          <li class="sense" sensenum="1" id="take_sng_167">
            <span class="def">to look or behave like an older member of your family</span>
          </li>
        </ol>
      </span>
    </div>
  </div>
</body>
</html>''';

/// What Cloudflare serves instead of an entry.
const String oaldBlockedPage = '''
<!doctype html>
<html>
<head><title>Attention Required! | Cloudflare</title></head>
<body>
  <h1>Sorry, you have been blocked</h1>
  <p>Please enable cookies.</p>
  <p>This website is using a security service to protect itself from online attacks.</p>
</body>
</html>''';

/// OALD's "did you spell it correctly?" page (the body of a 404 in the live
/// site; kept as 200 here so the parser's own check is exercised too).
const String oaldSuggestionPage = '''
<!doctype html>
<html>
<head><title>zzzznotaword - Did you spell it correctly? Alternative spellings from Oxford Advanced Learner&apos;s Dictionary</title></head>
<body>
  <div id="search-results"><h1>Did you spell it correctly?</h1></div>
</body>
</html>''';

/// A 200 page that is not a dictionary entry at all.
const String oaldPlainPage = '''
<!doctype html>
<html>
<head><title>Something else</title></head>
<body><h1>Hello</h1><p>No dictionary here.</p></body>
</html>''';

/// An entry header with no readable sense: the page structure changed.
const String oaldNoSensesPage = '''
<!doctype html>
<html>
<head><title>observe verb</title></head>
<body>
  <div id="entryContent" class="oald">
    <div class="entry" id="observe">
      <div class="webtop">
        <h1 class="headword">observe</h1>
        <span class="pos">verb</span>
      </div>
      <ol class="senses_multiple">
        <li class="sense"><span class="grammar">[transitive]</span></li>
      </ol>
    </div>
  </div>
</body>
</html>''';
