import type {
  ManualFigure,
  ManualSection,
  ManualSubsection,
} from "@/data/company-manual-content.ts";

export function ManualFigureBlock({ figure }: { figure: ManualFigure }) {
  return (
    <figure className="my-5 space-y-2">
      <img
        src={figure.src}
        alt={figure.caption}
        className="w-full rounded-xl border bg-card shadow-sm"
        loading="lazy"
      />
      <figcaption className="text-center text-xs text-muted-foreground italic px-2">
        {figure.caption}
      </figcaption>
    </figure>
  );
}

export function ManualSubsectionBlock({ item }: { item: ManualSubsection }) {
  return (
    <div className="rounded-xl border bg-card p-4 space-y-3">
      <h4 className="font-semibold text-sm text-[#1A5296]">{item.title}</h4>
      <p className="text-sm text-muted-foreground leading-relaxed">{item.body}</p>
      {item.bullets?.length ? (
        <ul className="list-disc pl-5 space-y-1 text-sm text-muted-foreground">
          {item.bullets.map((bullet) => (
            <li key={bullet}>{bullet}</li>
          ))}
        </ul>
      ) : null}
      {item.figure ? <ManualFigureBlock figure={item.figure} /> : null}
    </div>
  );
}

export function ManualSectionBlock({ section }: { section: ManualSection }) {
  return (
    <section id={section.id} className="scroll-mt-24 space-y-4">
      <h2 className="text-xl font-extrabold tracking-tight text-[#1A5296]">{section.title}</h2>
      {section.intro ? <p className="text-sm text-muted-foreground">{section.intro}</p> : null}
      {section.paragraphs?.map((paragraph) => (
        <p key={paragraph} className="text-sm leading-relaxed">
          {paragraph}
        </p>
      ))}
      {section.bullets?.length ? (
        <ul className="list-disc pl-5 space-y-1.5 text-sm leading-relaxed">
          {section.bullets.map((bullet) => (
            <li key={bullet}>{bullet}</li>
          ))}
        </ul>
      ) : null}
      {section.numbered?.length ? (
        <ol className="list-decimal pl-5 space-y-1.5 text-sm leading-relaxed">
          {section.numbered.map((item) => (
            <li key={item}>{item}</li>
          ))}
        </ol>
      ) : null}
      {section.figure ? <ManualFigureBlock figure={section.figure} /> : null}
      {section.subsections?.length ? (
        <div
          className={
            section.id === "owner" ||
            section.id === "commissions" ||
            section.id === "finance" ||
            section.id === "scanner"
              ? "grid gap-4 md:grid-cols-2"
              : "space-y-3"
          }
        >
          {section.subsections.map((item) => (
            <ManualSubsectionBlock key={item.title} item={item} />
          ))}
        </div>
      ) : null}
    </section>
  );
}
