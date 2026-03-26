# Most AI web search is broken for on-device agents

The problem is not search.

It is context collapse.

Most web tools for agents were built for big cloud models with big context windows. You search, fetch a few pages, dump a bunch of text into the model, and let it sort things out.

That works when the model has room to be sloppy.

It does not work when the agent is running on-device with 4K of working context.

In that world, every extra paragraph is expensive. Every page summary steals space from actual reasoning. Every "helpful" chunk of retrieved text makes the agent a little worse at the next step.

That is the part I think people still underestimate.

Small-context agents do not fail because they cannot find information.

They fail because their retrieval stack trashes the same context window they need for planning, tool use, and decision-making.

So if we are serious about on-device agents, I do not think we need a slightly better search wrapper.

I think we need a different architecture.

We are rebuilding `WebSearchTool` in Swarm around one simple idea:

**A webpage should not become prompt text by default. It should become memory.**

That sounds subtle. It is not.

The standard pipeline is basically:

```text
webpage -> markdown -> prompt
```

Fast to build. Easy to demo. Bad for real agent work.

You lose structure too early. You flatten docs, tables, forums, code blocks, and PDFs into the same text soup. Then you make the model carry that soup around while it tries to think.

I do not want that.

The pipeline we want looks more like this:

```text
raw artifact -> normalized document -> section chunks -> semantic core -> final 4K answer
```

That means:

- keep the source artifact
- parse the page into a structured document
- split it into section-level chunks with provenance
- store those chunks in Wax for local recall
- compress only the parts that matter for the current question

Only then does anything reach the agent's working context.

## What the API should feel like

The first thing that mattered to me here was that the API should look calm.

Not ten knobs at the call site. Not giant request payloads. Not "please manually assemble your retrieval stack" energy.

If web memory is configured, agents should just get the behavior.

```swift
import Swarm

await Swarm.configure(
    web: .init(
        apiKey: env("TAVILY_API_KEY"),
        persistFetchedArtifacts: true,
        maxGroundedFetches: 3,
        maxEvidenceSections: 6
    )
)

let agent = try Agent(
    "Answer with citations. Keep the first response compact."
)
```

That is the right shape.

You configure the web layer once. The agent gets ambient `websearch`. You do not make every call site repeat the same retrieval plumbing forever.

## What changes for the agent

The important thing is that we stop pretending every page deserves a full summary.

Usually it does not.

If the agent is trying to answer one specific question, the system should pull the two or three sections that matter for that question. Not write a polite summary of the whole site. Not include the company history. Not drag in the nav, footer, and onboarding fluff that every docs site repeats forever.

That is where query-conditioned extraction matters.

If the agent asks about rate limits, I want the rate limit section.

Not the "why we built this product" paragraph.

Not the getting started page.

Not the footer.

Just the relevant evidence.

Here is the behavior we are aiming for from the agent side:

```swift
let result = try await agent.run("""
Use websearch in ground mode.
Question: What changed recently in Swift 6.2 concurrency?
Return the shortest cited answer first.
""")
```

That snippet looks boring, which is good.

The complexity should live under the surface:

- local-first recall
- live fetch when needed
- section ranking against the current goal
- cross-page grounding
- compact first answer
- expand only when needed

The API should not scream all of that at you.

## The mental model

I think this is the cleanest way to explain it:

```swift
// Bad
let pageText = try await fetch(url)
let answer = try await model.respond(to: pageText)

// Better
let artifact = try await web.ingest(url)
let evidence = try await web.retrieve(goal: query, from: artifact)
let answer = try await web.pack4K(evidence)
```

That second block is not meant to be literal public API.

It is the architectural point.

The web page is not the thing the model should carry around.

The evidence is.

## Why this matters for deep research

People talk about deep research like the big question is whether a local agent can search enough sources.

I think the better question is whether it can accumulate evidence without replaying the whole internet into its prompt every turn.

That is a memory problem, not a search problem.

A real on-device research loop should look like this:

1. Find candidate pages.
2. Extract the relevant sections.
3. Store them.
4. Compare claims across sources.
5. Return one compact, cited answer.
6. Expand only when needed.

The first response should be small.

Not empty. Not vague. Small.

One answer. A few evidence snippets. Citations. Pointers back to stored artifacts.

That is how you stop the context window from turning into a landfill.

## What "good web search" means in a 4K world

For a giant cloud model, "good" often means broad recall and lots of raw text.

For a 4K on-device agent, "good" means context discipline.

Did the system fetch what mattered?

Did it preserve useful structure?

Did it avoid dragging irrelevant text into the prompt?

Did it keep citations attached?

Did it let the agent go deeper without starting over?

That is the bar.

We are also treating Foundation Models the right way, I think: optional, late, and non-essential.

If they are available on Apple 26, great. They can help with the last-mile compression step.

But if the whole system depends on a foundation model rewriting retrieval output into something usable, then the retrieval design is weak.

The system should already know how to preserve structure, rank evidence, dedupe sources, and fit the useful bits into a tiny budget.

The model can polish.

It should not rescue.

## The real ambition

So no, I do not think the interesting challenge here is "build web search for agents."

The interesting challenge is this:

**Build a web memory plane for agents that cannot afford context waste.**

That is a very different problem.

And I think it is the right one.

Because once you see the web as memory instead of prompt text, a lot of design decisions get cleaner.

Search becomes candidate generation.

Fetch becomes ingestion.

Summarization becomes query-conditioned compression.

Deep research becomes evidence management.

And the context window stops being a trash can.

That is the direction we are taking with Swarm.

If we get it right, a 4K on-device agent will not just be able to search the web.

It will be able to live on it.

---

## Optional diagram 1

```svg
<svg width="1200" height="260" viewBox="0 0 1200 260" fill="none" xmlns="http://www.w3.org/2000/svg">
  <style>
    .bg { fill: #ffffff; }
    .box { fill: #f7f7f5; stroke: #111111; stroke-width: 2; rx: 18; }
    .text { fill: #111111; font-family: -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif; font-size: 24px; font-weight: 600; }
    .sub { fill: #555555; font-family: -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif; font-size: 16px; }
    .arrow { stroke: #111111; stroke-width: 2.5; stroke-linecap: round; }
  </style>
  <rect class="bg" width="1200" height="260"/>
  <rect class="box" x="30" y="70" width="180" height="110" rx="18"/>
  <text class="text" x="120" y="115" text-anchor="middle">Raw artifact</text>
  <text class="sub" x="120" y="145" text-anchor="middle">html / pdf / text</text>

  <path class="arrow" d="M220 125H270"/>
  <path class="arrow" d="M260 115L270 125L260 135"/>

  <rect class="box" x="280" y="70" width="200" height="110" rx="18"/>
  <text class="text" x="380" y="115" text-anchor="middle">Normalized doc</text>
  <text class="sub" x="380" y="145" text-anchor="middle">clean structure + metadata</text>

  <path class="arrow" d="M490 125H540"/>
  <path class="arrow" d="M530 115L540 125L530 135"/>

  <rect class="box" x="550" y="70" width="180" height="110" rx="18"/>
  <text class="text" x="640" y="115" text-anchor="middle">Sections</text>
  <text class="sub" x="640" y="145" text-anchor="middle">chunked + cited</text>

  <path class="arrow" d="M740 125H790"/>
  <path class="arrow" d="M780 115L790 125L780 135"/>

  <rect class="box" x="800" y="70" width="180" height="110" rx="18"/>
  <text class="text" x="890" y="115" text-anchor="middle">Semantic core</text>
  <text class="sub" x="890" y="145" text-anchor="middle">query-relevant only</text>

  <path class="arrow" d="M990 125H1040"/>
  <path class="arrow" d="M1030 115L1040 125L1030 135"/>

  <rect class="box" x="1050" y="70" width="120" height="110" rx="18"/>
  <text class="text" x="1110" y="115" text-anchor="middle">4K answer</text>
  <text class="sub" x="1110" y="145" text-anchor="middle">small, cited</text>
</svg>
```

## Optional diagram 2

```svg
<svg width="1200" height="520" viewBox="0 0 1200 520" fill="none" xmlns="http://www.w3.org/2000/svg">
  <style>
    .bg { fill: #ffffff; }
    .title { fill: #111111; font-family: -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif; font-size: 28px; font-weight: 700; }
    .label { fill: #111111; font-family: -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif; font-size: 22px; font-weight: 600; }
    .sub { fill: #666666; font-family: -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif; font-size: 16px; }
    .frame { fill: #fafaf8; stroke: #111111; stroke-width: 2; rx: 20; }
    .bad { fill: #ffd9d2; stroke: #111111; stroke-width: 1.5; rx: 12; }
    .good { fill: #dff3e4; stroke: #111111; stroke-width: 1.5; rx: 12; }
    .neutral { fill: #f2f2ef; stroke: #111111; stroke-width: 1.5; rx: 12; }
  </style>
  <rect class="bg" width="1200" height="520"/>
  <text class="title" x="600" y="50" text-anchor="middle">Two ways to give a 4K agent web context</text>

  <rect class="frame" x="40" y="90" width="520" height="380" rx="20"/>
  <text class="label" x="70" y="130">Bad path</text>
  <text class="sub" x="70" y="155">web pages become prompt text</text>

  <rect class="bad" x="70" y="190" width="460" height="46" rx="12"/>
  <rect class="bad" x="70" y="248" width="460" height="46" rx="12"/>
  <rect class="bad" x="70" y="306" width="460" height="46" rx="12"/>
  <rect class="bad" x="70" y="364" width="460" height="46" rx="12"/>
  <text class="sub" x="300" y="219" text-anchor="middle">page summary 1</text>
  <text class="sub" x="300" y="277" text-anchor="middle">page summary 2</text>
  <text class="sub" x="300" y="335" text-anchor="middle">page summary 3</text>
  <text class="sub" x="300" y="393" text-anchor="middle">page summary 4</text>

  <rect class="neutral" x="70" y="422" width="460" height="28" rx="10"/>
  <text class="sub" x="300" y="441" text-anchor="middle">little room left for reasoning</text>

  <rect class="frame" x="640" y="90" width="520" height="380" rx="20"/>
  <text class="label" x="670" y="130">Better path</text>
  <text class="sub" x="670" y="155">web pages become local evidence</text>

  <rect class="neutral" x="670" y="190" width="460" height="46" rx="12"/>
  <text class="sub" x="900" y="219" text-anchor="middle">stored artifacts in Wax</text>

  <rect class="neutral" x="670" y="248" width="460" height="46" rx="12"/>
  <text class="sub" x="900" y="277" text-anchor="middle">section chunks + citations</text>

  <rect class="good" x="670" y="320" width="460" height="54" rx="12"/>
  <text class="sub" x="900" y="343" text-anchor="middle">1 compact answer</text>
  <text class="sub" x="900" y="362" text-anchor="middle">3 to 5 evidence snippets + refs</text>

  <rect class="good" x="670" y="392" width="460" height="58" rx="12"/>
  <text class="sub" x="900" y="416" text-anchor="middle">most of the 4K window stays free</text>
  <text class="sub" x="900" y="435" text-anchor="middle">for planning, tool use, and reasoning</text>
</svg>
```
