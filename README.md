Why `nimp` { pronounced like "chimp" and about as smart ;) }
============================================================
`nimp` arose from frustrations trying to get `nimble` maintainers to let package
authors decide -- on just about everything (combined w/a resolution I have made
to be a "less abstract" complainer).  Instead of trusting package authors to
write a task that installs a binary executable, `nimble` tries to guess all it
needs to do that.  This ends with second-guessing package authors too much &
making the whole problem harder.

As one example, nimble wants both specific and suspect "package structure" and
noisily complains when it does not get it.  It is suspect since 85% of `nimble`
packages are pure source code libraries more akin to C++ template header libs or
Pure Python `.py` files than to `.dll/.so` shared libs.  A natural layout of
such packages, single or multi-module, is `pkg/[modA.nim, modB.nim]`.  (This
notation converts to Nim `import` notation via deleting the ".nim".)  With this
layout, usage by clients is `git clone` with an optional `--path` augmentation
by `nim.cfg/config.nims`.  Without augmentation, one `--path` entry covers a
whole hierarchy of deps via `import foo/bar`.  With augmentation, client code
can simply `import bar` - unless it's likely to be ambiguous in which case they
`import foo/bar`.

Rather than support this simple mode of authorship/operation, `nimble` actively
discourages it and makes various rules/abstractions about "hybrid" or not kinds
of layouts and so on.  Over 91% of packages (700/768) with `src/` have only one
`.nim` file there.  Besides being none of `nimble`'s business in the first
place, it seems tilted toward rare executable and multi- module cases not common
library cases.  As seen in the final section, `src/` makes search path-based
compatibility have occasional collisions.  Pushing `src/` and then "reversing
it" at install time is thus worse than having no package manager at all for the
vast majority of current packages.

"Guessing" can also fail/be limited in many other ways.  There may be media file
assets or any number of do-this-at-install time needs.  Package authors, not
package managers, know the most about any number of other aspects of completing
an install.  There is simply no guessing everything.  Any package manager should
at least allow override of almost everything by the package.

So, how does `nimp` work?
=========================
`nimp` needs nothing but the stdlib and the code is like 300 lines and is a real
reference to how it works.  It is all very YAGNI.  The 20 second usage summary
is to `nimp get lc nim c -d:release` and `nimp up` to `git pull` in all repos.
Slightly more detail is available by running `nimp` with no arguments.

As per "Why", `nimp` assists but noes not constrain package authors & installers
in an "open architecture" way.  The present design is generated-if-missing
NimScripts a package author can tune or replace outright as desired.  `nimp`
doesn't over-write pre-existing scripts, giving package authors total control.
{`nim.cfg --path` generation & nimble-compatibility `src/` symlink garbage are
arguably guesswork that could be profitably delegated to package authors with
generated defaults..}

Scripts are in `<myPackage>/"pkg/"` or `%/myPackage`.  There are "hooks" for the
various package life cycle events.  `pkg/install.nims` compiles&installs binary
executables a package may contain.  The default generated `pkg/install.nims`
allows adjusting the entire Nim compile line (e.g. `nim e pkg/install.nims
nim-1.2.x cpp -d:danger ...`).  This is also propagated from the command
parameters after `nimp get pkg [nim cpp ...]`.  So, users can say `nimp get lc
nim-1.3.7 c -d:danger --gc:arc`, for example.

These hook scripts could be "tasks", but having separate files simplifies life.
Every tool to list/diff/patch/manage versions of/etc. for files carries over.
Rather than "custom tasks" you just add a new script.  Rather than a new package
manager command to list tasks, users can just list files in `pkg/`.  A simple
`pkg/test.nim` convention, like that generated by `nimp init`, fills the hole of
the `nimble` "test" task.  The only "standardization" needed is a name and how
to invoke it.  `nim e` or `nim r` on real files are as good as nimble tasks.

`nimp` tries for no mandates.  If you like `nake`, `cmake`, `scons`, etc., call
it from the installer script.  `pkg/install.nims` need have just one line to
`exec "make -f ../Makefile"` or some such.  You don't *have* to propagate such
full-nim-compile-line parameters (although users may complain if you do not).

There are other hook scripts.  Right now I use them to fix dependency packages:
`pkg/post_checkout.nims`, `pkg/pre_pull.nims`, `pkg/post_pull.nims`.  These let
non-package-maintainers "massage" imperfect packages to be more compliant with
an installed package set.  For example, I have had a tiny patch I keep against
@alaviss 's `nim.nvim` package.  With a patch file, and simple NimScripts, I
allow `nimp up` to reverse my patch, `git pull`, & re-apply my patch, allowing
me to stay up-to-date-but-for-my-patch.  One can also use these to make
otherwise `nimp`-uninstallable packages work fine as per the next section.

As evident from `nim.nvim` above, `nimp get|up` also work on *non-Nim repos* &
URIs not in `packages.json`.  `nimp u`  runs in parallel and is usually very
fast (10 seconds to git pull *the whole Nimbleverse* on a fast network) and only
emits output for things not up-to-date/failing.

How well does `nimp` work?
==========================
`nimp` is still at a proof of concept stage. It may have numerous bugs/failings,
but it works ok for me.  To test it, I cloned all clonable nimble packages in
`packages.json` on 2020/10/04.  Then I tried to build (with a devel compiler)
the 220 packages that with non-empty `nimble` `bin` directives.  With scripts
under `'%'` in this repo, I could build all the same packages that `nimble`
could also successfully install.  (But for `nimwc` which needs a fix to use the
VC head of one if its deps.)  I also tried it against the `nimx` library
package which has complex & non-nimble deps and `nimterop`, depended upon for
code generation instead of depended upon for `import`.  No real problems.

The `%` patches I had to do are basically all derived from needing deep `--path`
settings to be backward compatible with awkward `src/` layouts nimble has long
encouraged.  Were package qualification commonplace, they would likely not have
been needed.  Only 6 packages of 159 have unqualified name collisions relevant
for producing all the executables and require only minor tweaks.  Now, over 60
packages of the 220 that have a `bin=` outright fail (likely due to Nim language
evolution).  This ~6 package fix-up is actually 10x less the troubles one has
with the ecosystem from staleness.  This is one way to quantify "works ok".  I
think about half of the 60 failures are just nim-devel vs. nim-1.2.0 things.

I also realize this is a very partial test (only 15%!).  Compiling to a binary
and searching for Error: was a simple, easy thing for me to run/test.  Note that
the automated fix up style here means `nimp` users need not rely on any real
approval from *anyone*..neither `nimble` nor dependency maintainers.  If you are
a package-user who cannot persuade a package-maintainer to fix up an origin repo
then I am happy to take PRs for `%` fix-up scripts.  Also, for the 85% that do
not install binary executables, the install action is really just git clone.
I did test `nimp dump req` on the entire Nimbleverse and it also worked fine
and produced a nice dependency graph for me.  Oh, and I tested `nimp init`
converting the single file script to a nimble package and `nimp publish` when
publishing `nimp` itself, both of which worked fine. :)

At present there seems little need for `==` or `<` version requirements -- the
only time multiple installed versions become needed.  Earlier versions of Nim
itself seem far more valuable (and are already supported by `nimp`).  `nimp` has
some commented out code sketching how to provide a private hierarchy with
whatever versions.
