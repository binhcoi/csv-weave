import { screen, within } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import { renderApp } from './test/render'

describe('App', () => {
  it('redirects the root to the help page', () => {
    renderApp('/')

    expect(screen.getByRole('heading', { level: 1, name: 'Help' })).toBeInTheDocument()
  })

  it.each([
    ['/help', 'Help'],
    ['/file-types', 'File types'],
    ['/maps', 'Transformation maps'],
    ['/files', 'Files and runs'],
  ])('renders %s', (path, heading) => {
    renderApp(path)

    expect(screen.getByRole('heading', { level: 1, name: heading })).toBeInTheDocument()
  })

  it('explains the workflow on the help page', () => {
    renderApp('/help')

    expect(screen.getByRole('heading', { level: 2, name: 'Typical workflow' })).toBeInTheDocument()
    expect(
      screen.getByRole('heading', { level: 2, name: 'Runs and rejection reports' }),
    ).toBeInTheDocument()
  })

  it('shows navigation to every working area', () => {
    renderApp('/help')

    const nav = within(screen.getByRole('navigation', { name: 'Main navigation' }))
    expect(nav.getByRole('link', { name: /File types/ })).toHaveAttribute('href', '/file-types')
    expect(nav.getByRole('link', { name: /Transformation maps/ })).toHaveAttribute('href', '/maps')
    expect(nav.getByRole('link', { name: /Files and runs/ })).toHaveAttribute('href', '/files')
    expect(nav.getByRole('link', { name: /Help/ })).toHaveAttribute('href', '/help')
  })

  it('marks the current area in the navigation', () => {
    renderApp('/file-types')

    const nav = within(screen.getByRole('navigation', { name: 'Main navigation' }))
    expect(nav.getByRole('link', { name: /File types/ })).toHaveAttribute('aria-current', 'page')
    expect(nav.getByRole('link', { name: /Help/ })).not.toHaveAttribute('aria-current')
  })

  it('sets the document title per screen', () => {
    renderApp('/maps')

    expect(document.title).toBe('Transformation maps · CSVWeave')
  })

  it('offers a way back from unknown addresses', () => {
    renderApp('/no-such-page')

    expect(screen.getByRole('heading', { level: 1, name: 'Page not found' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: 'Go to the help page.' })).toHaveAttribute(
      'href',
      '/help',
    )
  })
})
