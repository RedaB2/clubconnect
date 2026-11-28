# Joining a club

A first-time member has two questions. “Is this my club?” and “What will people here see about me?” Club Connect answers both before the member joins. A link carries the club through email verification so someone who came for MENASA can find it again after creating a profile.

## Three approaches we considered

| Approach | What it gives a new member | Fit for the USC pilot |
| --- | --- | --- |
| Feature tour | A walkthrough can introduce Events, People, Messages, and Wallet before sign-in. | Every new member would have to remember controls they cannot use yet. Show the actual event and ticket controls when someone RSVPs. Apple recommends short onboarding and teaching in context. [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/onboarding) |
| Personalize first | Discord asks questions that change which roles and channels a new arrival sees. Duolingo asks about experience to choose a starting point. | Graduation term changes the directory someone appears in. Interests and experience can start conversations later. Asking for them during entry adds work before they change anything on screen. [Discord community onboarding](https://support.discord.com/hc/en-us/articles/11074987197975-Community-Onboarding-FAQ) · [Getting started on Duolingo](https://blog.duolingo.com/duolingo-101-how-to-learn-a-language-on-duolingo/) |
| Start with the invitation | Slack lets someone verify a mailbox and accept a particular workspace invitation. Flighty gives people a chance to experience its features on an actual flight. | A club link tells us what the visitor came to do. Show the destination, verify their email, collect the few details peers need, then offer campus enrollment or an alumni membership request. This is the pilot’s first-run flow. [Joining a Slack workspace](https://slack.com/help/articles/212675257-Join-a-Slack-workspace) · [Flighty’s first flight](https://flighty.com/help/complimentary-flighty-pro-flight) |

## The first visit

- A campus visitor sees a short welcome, verifies their USC address, creates a profile, then joins a club or creates one. Returning members can go straight to sign-in.
- An alum can sign up with a personal email and save their profile before choosing any club. A link can point them toward a particular club. They can find another club, write an optional note, request admission, and check each decision independently.
- Members enter their name, spring or fall graduation term, and year. People still studying choose a class standing. Photo, interests, major, and experience can be added from Profile whenever the member wants.
- After enrollment, the club page shows its upcoming events. Calendar, Wallet, and camera actions appear at the point of use.

## How alumni qualify

| Model | What organizers and alumni would need to do |
| --- | --- |
| Organizer invites an email address | Gives a known alum a direct route, but depends on an organizer knowing the alum’s current address and initiating each invitation. |
| Open membership after a personal email check | Easy to start, but email verification alone cannot establish club affiliation. |
| **Open signup with approval per club** | Alumni can find former clubs themselves. Each organizer reviews a name, graduation term, verified email, and optional note before admitting that person. We chose this for the pilot. |

Discord’s member application model has a similar boundary between applying and accessing a community. [Discord member applications](https://support.discord.com/hc/en-us/articles/29729107418519-Server-Member-Applications)

A pending applicant can see the club’s public identity and their request status. Approval opens its roster, events, and messages between fellow members. Withdrawal frees the applicant to request again. After a decline, the applicant can submit a new request with more context. Club organizers decide affiliation. Verifying a personal address proves control of that mailbox.

## Visual choices

Flighty gives the most timely information the strongest position. We use that hierarchy for names, unread messages, and event dates. Bitrig presents creations through recognizable visual previews, and Duolingo uses a consistent illustration language to make related interactions feel like one product. Here, the welcome photograph, member portraits, warm surfaces, and consistent type give People and Messages an identity of their own. The native tab bar, back gesture, search, and split navigation stay familiar. [Flighty](https://flighty.com/) · [Bitrig](https://bitrig.com/) · [Duolingo design guidelines](https://design.duolingo.com/)

These are design decisions for the pilot. Whether members finish the flow and find an event or person they care about needs to be evaluated with actual testers.
