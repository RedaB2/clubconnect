import { Buffer } from "node:buffer";
import { PKPass } from "passkit-generator";
import icons from "./icons.json" with { type: "json" };

interface EventPassSnapshot {
  club: { name: string; accentHex: string };
  events: {
    id: string;
    title: string;
    startsAt: string;
    endsAt: string;
    location: string;
  }[];
  // The snapshot RPC restricts tickets to the calling member, including for admins.
  tickets: { id: string; eventID: string; code: string; checkedIn: boolean }[];
}

function fail(message: string, status: number) {
  return Response.json({ message }, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}

function signingMaterial(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error("Missing Wallet signing configuration");
  return Buffer.from(value, "base64");
}

function colors(hex: string) {
  const fallback = "29483D";
  const value = /^#?[0-9a-f]{6}$/i.test(hex) ? hex.replace("#", "") : fallback;
  const [r, g, b] = [0, 2, 4].map((i) => parseInt(value.slice(i, i + 2), 16));
  const [lr, lg, lb] = [r, g, b].map((c) => {
    const s = c / 255;
    return s <= 0.04045 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
  });
  const bright = 0.2126 * lr + 0.7152 * lg + 0.0722 * lb > 0.179;
  const text = bright ? "rgb(0, 0, 0)" : "rgb(255, 255, 255)";
  return {
    backgroundColor: `rgb(${r}, ${g}, ${b})`,
    foregroundColor: text,
    labelColor: text,
  };
}

function signPass(snapshot: EventPassSnapshot, eventID: string) {
  const match = (id: string) => id.toLowerCase() === eventID.toLowerCase();
  const event = snapshot.events.find((event) => match(event.id));
  const ticket = snapshot.tickets.find((ticket) => match(ticket.eventID));
  if (!event || !ticket) return fail("RSVP to this event to add a pass.", 404);
  if (ticket.checkedIn) {
    return fail("This ticket has already been checked in.", 409);
  }
  if (Date.parse(event.endsAt) <= Date.now()) {
    return fail("This event has ended.", 410);
  }

  const pass = new PKPass(
    Object.fromEntries(
      Object.entries(icons).map((
        [name, data],
      ) => [name, Buffer.from(data, "base64")]),
    ),
    {
      wwdr: signingMaterial("WALLET_WWDR_CERT_B64"),
      signerCert: signingMaterial("WALLET_SIGNER_CERT_B64"),
      signerKey: signingMaterial("WALLET_SIGNER_KEY_B64"),
    },
    {
      formatVersion: 1,
      passTypeIdentifier: "pass.com.redaboutayeb.clubconnect",
      teamIdentifier: "AD6Q827Z79",
      serialNumber: ticket.id,
      organizationName: snapshot.club.name,
      logoText: snapshot.club.name,
      description: `${event.title} event ticket`,
      sharingProhibited: true,
      ...colors(snapshot.club.accentHex),
    },
  );
  pass.type = "eventTicket";
  pass.primaryFields.push({ key: "event", label: "EVENT", value: event.title });
  pass.secondaryFields.push({
    key: "date",
    label: "WHEN",
    value: event.startsAt,
    dateStyle: "PKDateStyleMedium",
    timeStyle: "PKDateStyleShort",
  });
  pass.auxiliaryFields.push({
    key: "location",
    label: "WHERE",
    value: event.location,
  });
  pass.backFields.push({
    key: "entry",
    label: "Entry",
    value: "Show the QR code at the door to check in.",
  });
  pass.setRelevantDate(new Date(event.startsAt));
  pass.setRelevantDates([{ startDate: event.startsAt, endDate: event.endsAt }]);
  pass.setExpirationDate(new Date(event.endsAt));
  pass.setBarcodes({
    format: "PKBarcodeFormatQR",
    message: ticket.code,
    messageEncoding: "iso-8859-1",
    altText: ticket.code,
  });

  return new Response(new Uint8Array(pass.getAsBuffer()), {
    headers: {
      "Content-Type": "application/vnd.apple.pkpass",
      "Content-Disposition": 'attachment; filename="event-ticket.pkpass"',
      "Cache-Control": "private, no-store",
    },
  });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return fail("Use POST.", 405);
  const authorization = request.headers.get("Authorization");
  if (!authorization?.match(/^Bearer [^\s]+$/i)) {
    return fail("Sign in to add a pass.", 401);
  }
  const body = await request.json().catch(() => null);
  if (
    typeof body?.eventID !== "string" || !body.eventID ||
    body.eventID.length > 128
  ) {
    return fail("An event ID is required.", 400);
  }
  try {
    const url = Deno.env.get("SUPABASE_URL");
    const apiKey = Deno.env.get("SUPABASE_ANON_KEY") ??
      JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") || "{}").default;
    if (!url || !apiKey) return fail("Wallet signing is unavailable.", 503);

    // PostgREST verifies the caller's JWT and evaluates the same membership checks as the app.
    const response = await fetch(`${url}/rest/v1/rpc/snapshot`, {
      method: "POST",
      headers: {
        Authorization: authorization,
        apikey: apiKey,
        "Content-Type": "application/json",
      },
      body: "{}",
    });
    if ([401, 403].includes(response.status)) {
      return fail("Sign in to add a pass.", response.status);
    }
    if (!response.ok) return fail("Tickets are temporarily unavailable.", 503);
    return signPass(await response.json(), body.eventID);
  } catch {
    return fail("Wallet signing is temporarily unavailable.", 503);
  }
});
