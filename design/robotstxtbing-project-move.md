# robotstxtbing work moved to a standalone FP project

On 2026-07-18, robotstxtbing research, implementation, release, and adapter
planning moved from the robotstxtr FP project to the standalone FP project in
the sibling `robotstxt-cpp-bing` repository.

The canonical delivery epic is now `BING-uljhlerk`. The migration preserved
the 125 raw issue identities, hierarchy, dependencies, statuses, and comments;
their display prefix changed from `ROBO-` to `BING-`. This includes the
124-issue delivery hierarchy and the earlier pre-spec issue, now
`BING-rvnkadzd`.

Do not create or resume robotstxtbing implementation work in the robotstxtr FP
project. Run `fp` from the sibling repository and use its `BING` project.
Robotstxtr retains one deliberate follow-up only:
`ROBO-xgjvnfii`, which independently verifies the completed, pinned
robotstxtbing release before robotstxtr adopts it.

The Bing design documents retained in this repository record architecture and
historical decisions. They do not make robotstxtr the implementation tracker.
